# -*- coding: utf-8 -*-
"""Join the two ledgers and say what the shadow arm has learned so far.

lea.csv is written by the Stop hook (what Lea's turn cost), shadow.csv by the shadow runner
(what a stock config cost on the same prompt, from the same starting directory). They are
separate files on purpose: two processes, no shared write.

**Dollars are not the headline, and the reason is measured, not assumed.** On the first three
pairs this collected, the Lea/stock cost ratio was 1.3x at turn 8 of a session, 6.9x at turn 23
and 5.7x at turn 27 - while the two arms' output token counts stayed within 10% of each other.
The ratio was tracking how deep into a session the prompt arrived, not which configuration
answered it: Lea answers inside a conversation and pays to re-read it on every turn, and the
shadow arm answers the same prompt from an empty context. That is a difference in the rig, not
in the ruleset, and collecting more of it would only measure it more precisely.

So this leads with the two quantities both arms produce under the same conditions - **turns and
output tokens** - which are also the two a ruleset actually moves. Dollars are reported per arm,
beside the input each arm had to carry, so the gap is visible rather than hidden inside a ratio.
A cost ratio is printed only over pairs where the two arms carried comparable input.

Usage:  python report.py
"""
import csv
import io
import json
import os
import statistics as st
import sys

# The prompts are Turkish and the Windows console defaults to cp1252, which cannot encode
# a dotless i. Without this the report dies mid-table on the first Turkish prompt it prints.
try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
except Exception:
    pass

HERE = os.path.dirname(os.path.abspath(__file__))


def load(name, key='id'):
    p = os.path.join(HERE, name)
    if not os.path.exists(p):
        return {}
    with io.open(p, encoding='utf-8-sig', newline='') as fh:
        return {r[key]: r for r in csv.DictReader(fh) if r.get(key)}


# Summed, not last-wins. One prompt can produce more than one lea.csv row: when a usage limit
# interrupts a task, Claude Code's own continuation finishes it at a later Stop, and that work
# is recorded against the prompt that started it rather than against a prompt the shadow arm
# never saw. Each Stop records only what happened since the previous one, so summing is exactly
# right and taking the last row would silently drop the larger half of the work.
SUMMED = ('cost_usd', 'turns', 'output_tokens', 'input_tokens', 'cache_read_tokens')


# Data imported from other machines. import.py merges each export zip in here and tags every row
# with `source` (machine/user) and `key` (source + id), because a pooled ledger with unlabelled
# rows cannot be read at all: model, budgets and configuration differ per install, so an install
# difference would read as a configuration difference.
#
# Until 2026-09-03 nothing read this directory. Imports landed and changed no report and no page,
# which is the worst kind of broken: it looks like it worked.
POOL = os.path.join(HERE, 'pool')


def load_pool(name, key='key'):
    p = os.path.join(POOL, name)
    if not os.path.exists(p):
        return {}
    with io.open(p, encoding='utf-8-sig', newline='') as fh:
        return {r[key]: r for r in csv.DictReader(fh) if r.get(key)}


def load_pool_lea():
    """Same summing as the local ledger, keyed by `key` so two machines cannot collide on an id.

    Run ids are timestamps plus a hash of the prompt, so two machines really can produce the
    same id for the same prompt in the same second. `key` is what keeps them apart.
    """
    return _sum_lea(load_pool('lea.csv').values(), 'key')


def load_lea():
    p = os.path.join(HERE, 'lea.csv')
    if not os.path.exists(p):
        return {}
    with io.open(p, encoding='utf-8-sig', newline='') as fh:
        return _sum_lea(csv.DictReader(fh), 'id')


def _sum_lea(rows, key):
    out = {}
    for r in rows:
        rid = r.get(key)
        if not rid:
            continue
        if rid not in out:
            out[rid] = dict(r)
            continue
        first = out[rid]
        for f in SUMMED:
            try:
                first[f] = str(float(first.get(f) or 0) + float(r.get(f) or 0))
            except ValueError:
                pass
        # The prompt arrived once, at the depth the first row recorded; a continuation of it
        # did not arrive again.
    return out


def num(row, field):
    try:
        return float(row.get(field) or '')
    except (TypeError, ValueError):
        return None


def carried(row):
    """Input tokens this arm had to read to answer: fresh plus cache reads.

    Empty for every row written before 2026-08-31, when the two ledgers started recording it.
    """
    a, b = num(row, 'input_tokens'), num(row, 'cache_read_tokens')
    if a is None and b is None:
        return None
    return (a or 0) + (b or 0)


def tok(v):
    if v is None:
        return '—'
    if v >= 1e6:
        return '%.1fM' % (v / 1e6)
    if v >= 1e3:
        return '%.0fk' % (v / 1e3)
    return '%d' % v


def ratio(a, b):
    return (a / b) if (a and b) else None


def pooled_prompts():
    """id -> prompt, out of the pool's prompts.jsonl. Keyed by id, not by key: export.ps1 writes
    the run id, having no idea what tag the importing machine will file it under."""
    p = os.path.join(POOL, 'prompts.jsonl')
    out = {}
    if not os.path.exists(p):
        return out
    for line in io.open(p, encoding='utf-8'):
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except ValueError:
            continue
        if rec.get('id'):
            out[rec['id']] = ' '.join(str(rec.get('prompt') or '').split())[:44]
    return out


def rows():
    """Local rows first, then everything imported from other machines.

    Both go through the same joining and the same pairing rules; what keeps them apart is the
    `source` field, which is 'local' here and machine/user for anything pooled. Nothing is
    merged into a single average - a difference between installs would otherwise read as a
    difference between configurations, which is the one comparison this whole rig exists to make.
    """
    lea, shadow = load_lea(), load('shadow.csv')
    for rid in sorted(set(lea) | set(shadow)):
        l, s = lea.get(rid, {}), shadow.get(rid, {})
        prompt = ''
        pf = os.path.join(HERE, 'runs', rid, 'prompt.txt')
        if os.path.exists(pf):
            prompt = ' '.join(io.open(pf, encoding='utf-8').read().split())[:44]
        yield _row(rid, 'local', l, s, prompt)

    pl, ps = load_pool_lea(), load_pool('shadow.csv')
    prompts = pooled_prompts()
    for key in sorted(set(pl) | set(ps)):
        l, s = pl.get(key, {}), ps.get(key, {})
        rid = l.get('id') or s.get('id') or key
        src = l.get('source') or s.get('source') or '?'
        yield _row(rid, src, l, s, prompts.get(rid, ''))


# How many files each arm actually changed, or None when that was never recorded.
#
# This is the column the ledger was missing, and its absence made the cost numbers unreadable.
# The first three comparable pairs had the shadow arm at 1.67x cheaper and Lea at 1.77x the
# turns - which says nothing at all until you know that on two of those three the shadow arm
# changed ZERO files. Doing less is always cheaper. A ratio between an arm that did the work and
# an arm that answered and stopped is arithmetic, not a measurement.
#
# Counted from the artifacts each arm leaves behind, which survive pruning: shadow.patch is a
# real diff, so its files are its `diff --git` headers; lea.stat is git --numstat, one line per
# file. None means "not recorded" and is kept distinct from 0, "recorded, and nothing changed".
def _changed(run_dir):
    lea = sh = None
    try:
        p = os.path.join(run_dir, 'shadow.patch')
        if os.path.exists(p):
            sh = sum(1 for ln in io.open(p, encoding='utf-8', errors='replace')
                     if ln.startswith('diff --git'))
        p = os.path.join(run_dir, 'lea.stat')
        if os.path.exists(p):
            lea = sum(1 for ln in io.open(p, encoding='utf-8', errors='replace') if ln.strip())
    except OSError:
        pass
    return lea, sh


def _row(rid, source, l, s, prompt):
        return dict(
            source=source,
            id=rid, prompt=prompt, when=(l.get('when') or s.get('when') or ''),
            model=l.get('model', ''), config=s.get('config', ''), rule=s.get('rule', ''),
            status=s.get('status', 'pending'), note=s.get('note', ''),
            lea_cost=num(l, 'cost_usd'), sh_cost=num(s, 'cost_usd'),
            lea_turns=num(l, 'turns'), sh_turns=num(s, 'turns'),
            lea_out=num(l, 'output_tokens'), sh_out=num(s, 'output_tokens'),
            lea_in=carried(l), sh_in=carried(s),
            depth=num(l, 'turns_before'),
            # Which install produced the row. Either ledger may carry it - the shadow runner and
            # the Stop hook write independently and one can exist without the other.
            user=(s.get('user') or l.get('user') or ''),
            host=(s.get('host') or l.get('host') or ''),
            lea_config=(l.get('lea_config') or ''),
            # Lea's cwd against the tree the shadow arm actually copied. Equal is the normal
            # case; different means the runner had to fall back to a project_roots entry.
            cwd=(l.get('cwd') or ''),
            tree_root=(s.get('tree_root') or ''),
            **dict(zip(('lea_files', 'sh_files'), _changed(os.path.join(HERE, 'runs', rid)))))


# A pair whose two arms started from different trees is a weaker thing than one whose arms did
# not, and the difference has to be visible rather than averaged in. It happens when the session's
# own directory could not be copied and the runner fell back to a project_roots entry: the prompt
# is the same and the turn counts still mean something, but the two diffs no longer share an
# ancestor, so nothing about the files each arm changed is comparable.
def substituted(r):
    root, cwd = (r.get('tree_root') or ''), (r.get('cwd') or '')
    return bool(root) and bool(cwd) and os.path.normcase(os.path.normpath(root)) != \
        os.path.normcase(os.path.normpath(cwd))


def paired(data):
    """Both arms answered the prompt, and both were priced."""
    return [r for r in data if r['status'] == 'ok' and r['lea_turns'] and r['sh_turns']]


def work_matched(r):
    """Did the two arms do a comparable amount of work, so a ratio between them means anything?

    Necessary because the first three pairs made the point loudly: the shadow arm came out 1.67x
    cheaper and, on two of the three, had changed no files at all. An arm that answers and stops
    is always cheaper than an arm that does the job, and no sample size fixes that - it is a
    different measurement, not a noisy one.

    True only when both counts are known and both arms are on the same side of "touched the
    tree". A prompt that is a question (neither arm changes anything) is a legitimate pair; a
    prompt where one arm edited files and the other did not is not.
    """
    lea, sh = r.get('lea_files'), r.get('sh_files')
    if lea is None or sh is None:
        return False
    return (lea > 0) == (sh > 0)


def comparable(data):
    """The pairs that are a measurement, by the one definition anything is allowed to cite.

    A pair is a measurement only if both arms were given the same problem, and a prompt sent
    mid-conversation is not that. "commit et" means something to Lea, which has the session, and
    nothing to a shadow run starting from an empty context in a copy of the directory: the two
    arms answer different questions, and their turns, output and cost describe different work.
    Only a prompt that opened its session qualifies (`depth == 0`), and even that is necessary
    rather than sufficient - one that refers to yesterday still refers to nothing here. Pairs
    whose shadow arm ran against a substituted tree are excluded and reported separately.

    This lives here rather than in each page that prints it because savings.py quotes the count
    in a published headline. Two definitions of "comparable" eventually disagree, and the one on
    the page is the one nobody thinks to re-check.
    """
    return [r for r in paired(data) if r['depth'] == 0 and not substituted(r)]


def main():
    data = list(rows())
    if not data:
        print('no shadow runs recorded yet')
        return

    # A pair is one prompt answered twice and finished twice. A truncated shadow run has a cost
    # and no result, and comparing it would read as "the stock config was cheaper" when it
    # simply stopped.
    pairs = paired(data)

    print('%-17s %-7s %13s %15s %17s  %s' %
          ('when', 'config', 'turns L/S', 'output L/S', 'carried in L/S', 'prompt'))
    for r in pairs:
        print('%-17s %-7s %13s %15s %17s  %s' % (
            r['when'][:16], r['config'] or '—',
            '%d / %d' % (r['lea_turns'], r['sh_turns']),
            '%s / %s' % (tok(r['lea_out']), tok(r['sh_out'])),
            '%s / %s' % (tok(r['lea_in']), tok(r['sh_in'])),
            r['prompt']))

    # Both rules are defined at module level so the pages that quote them cannot drift.
    opening = [r for r in pairs if r['depth'] == 0]
    later = [r for r in pairs if r['depth'] is None or r['depth'] > 0]
    opening_same = comparable(data)
    opening_moved = [r for r in opening if substituted(r)]

    print('\n%d prompt(s) recorded, %d paired, %d of those comparable.'
          % (len(data), len(pairs), len(opening_same)))
    if opening_moved:
        print('\n%d pair(s) opened their session but ran against a different tree than Lea did -'
              % len(opening_moved))
        print('the working directory could not be copied, so the runner used a project_roots')
        print('entry instead. Turns and output still describe the same prompt; the two diffs do')
        print('not share an ancestor, so what each arm changed on disk is not comparable.')
        for r in opening_moved:
            print('    %s  Lea in %s' % (r['when'][:16], r.get('cwd') or '?'))
            print('    %s  shadow in %s' % (' ' * 16, r.get('tree_root') or '?'))

    # More than one install can write this ledger - two Windows users on one machine share it,
    # and each carries its own account, budget and possibly its own ruleset. Printed per install
    # because a difference between installs would otherwise read as a difference between configs,
    # and because a profile that is silently contributing nothing is worth seeing.
    # Where the rows came from. Local and pooled are counted apart on purpose: another machine
    # runs a different model mix under different budgets, so folding it into one number would
    # make an install difference look like a configuration difference.
    by_source = {}
    for r in data:
        b = by_source.setdefault(r['source'], {'rows': 0, 'pairs': 0, 'comparable': 0})
        b['rows'] += 1
        if r in pairs:
            b['pairs'] += 1
        if r in opening_same:
            b['comparable'] += 1
    if len(by_source) > 1:
        print('\nwhere the rows came from:')
        for src, b in sorted(by_source.items()):
            print('  %-28s %4d row(s), %d paired, %d comparable'
                  % (src, b['rows'], b['pairs'], b['comparable']))
        print('  Pooled rows are never averaged with local ones. Another machine runs its own')
        print('  model mix under its own budgets; only same-source numbers compare.')
    elif os.path.isdir(POOL):
        print('\npool/ exists but holds nothing this report can use - `python import.py --list`')

    lea_rows = load_lea()
    installs = {}
    for r in lea_rows.values():
        k = (r.get('user') or '?', r.get('lea_config') or 'lea')
        v = installs.setdefault(k, {'n': 0, 'usd': 0.0})
        v['n'] += 1
        try:
            v['usd'] += float(r.get('cost_usd') or 0)
        except ValueError:
            pass
    sh_by_user = {}
    for r in data:
        u = (r.get('user') or '?')
        sh_by_user[u] = sh_by_user.get(u, 0) + 1
    if installs:
        print('\ninstalls writing this ledger:')
        for (user, cfg), v in sorted(installs.items()):
            flag = '' if cfg == 'lea' else '   <- NOT Lea; these rows are excluded from any Lea claim'
            print('  %-12s %-18s %4d Lea turns  $%8.2f   %4d shadow rows%s'
                  % (user, cfg, v['n'], v['usd'], sh_by_user.get(user, 0), flag))
    if later:
        spent = sum(r['sh_cost'] for r in later if r['sh_cost'])
        print('\n%d pair(s) came mid-conversation, so the shadow arm was answering a prompt it'
              % len(later))
        print('could not resolve - a different problem, not a cheaper answer to the same one.')
        print('They are kept out of every median below. They cost $%.2f to collect.' % spent)
        for r in later:
            print('    %-16s %s' % (r['when'][:16], r['prompt']))
    if not opening:
        print('\nNothing comparable yet: no paired prompt has opened a session.')
    else:
        # What each arm actually did, before any ratio is quoted over it. Printed first because
        # it is what decides whether the ratios below are a measurement at all.
        print('\nWhat each arm changed on disk (files):')
        for r in opening_same:
            print('    %-16s  Lea %-7s stock %-7s %s'
                  % (r['when'][:16],
                     '?' if r['lea_files'] is None else r['lea_files'],
                     '?' if r['sh_files'] is None else r['sh_files'],
                     r['prompt']))
        unusable = [r for r in opening_same if not work_matched(r)]
        if unusable:
            print('\n%d of those cannot carry a ratio: one arm did work the other did not, or the'
                  % len(unusable))
            print('file counts were never recorded. Cheaper is trivial when it means doing less,')
            print('so these are shown and not averaged.')

        # Ratios are taken over the pairs that passed the check above, not over every pair that
        # opened its session. The wider set produced "Lea takes 1.77x the turns" while two of its
        # three members had the stock arm changing nothing at all, which is not a finding about
        # the ruleset - it is a finding about what the stock arm declined to do.
        usable = [r for r in opening_same if work_matched(r)]
        turn_r = [x for x in (ratio(r['lea_turns'], r['sh_turns']) for r in usable) if x]
        out_r = [x for x in (ratio(r['lea_out'], r['sh_out']) for r in usable) if x]
        print('\nWhat the ruleset moves - both arms answered the same prompt from the same')
        print('directory AND did comparable work, so these compare directly')
        print('(below 1.00 means Lea did it with less):')
        if turn_r:
            print('  turns   median %.2fx   %s' % (st.median(turn_r),
                  ' '.join('%.2f' % x for x in turn_r)))
        if out_r:
            print('  output  median %.2fx   %s' % (st.median(out_r),
                  ' '.join('%.2f' % x for x in out_r)))
        if not turn_r:
            print('  nothing to average yet - see the file counts above.')
            print('  For reference only, over every session-opening pair regardless of what each')
            print('  arm did: turns %s, output %s. Do not quote these.'
                  % (' '.join('%.2f' % x for x in
                              [y for y in (ratio(r['lea_turns'], r['sh_turns'])
                                           for r in opening) if y]),
                     ' '.join('%.2f' % x for x in
                              [y for y in (ratio(r['lea_out'], r['sh_out'])
                                           for r in opening) if y])))

        print('\nWhat the rig moves - dollars. Each arm, and what it had to read:')
        for label, c, i in (('Lea  ', 'lea_cost', 'lea_in'), ('stock', 'sh_cost', 'sh_in')):
            costs = [r[c] for r in opening if r[c]]
            ins = [r[i] for r in opening if r[i] is not None]
            print('  %s  $%.4f over %d pair(s)%s' % (
                label, sum(costs), len(costs),
                (', median %s carried in per prompt' % tok(st.median(ins))) if ins else ''))

        # Only pairs where neither arm was carrying a conversation the other never saw can be
        # compared in dollars at all. Two-to-one is generous and still usually excludes a turn
        # taken deep into a session.
        matched = [r for r in usable if r['lea_in'] and r['sh_in'] and r['lea_in'] <= 2 * r['sh_in']]
        cost_r = [x for x in (ratio(r['lea_cost'], r['sh_cost']) for r in matched) if x]
        print('\nCost ratio, over the pairs where the two arms did comparable work AND carried')
        print('comparable input:')
        if cost_r:
            print('  median %.2fx over %d pair(s)' % (st.median(cost_r), len(cost_r)))
        else:
            missing = sum(1 for r in opening if r['lea_in'] is None or r['sh_in'] is None)
            print('  no comparable pair yet (%d of %d recorded before the ledgers kept the input'
                  ' counts; %d more failed the work check above).'
                  % (missing, len(opening), len(opening_same) - len(usable)))
        depthed = [r for r in opening if r['depth'] is not None and r['lea_cost'] and r['sh_cost']]
        if len(depthed) > 1:
            print('  for contrast, every pair by session depth:')
            for r in sorted(depthed, key=lambda r: r['depth']):
                print('    turn %-4d of its session   %.1fx' %
                      (r['depth'], r['lea_cost'] / r['sh_cost']))

    cut = [r for r in data if r['status'] == 'truncated']
    if cut:
        print('\n%d run(s) hit the per-run cap and were left out. Those prompts cost more than the'
              % len(cut))
        print('shadow budget allows; raise budget_usd_per_run and the purses to include them.')

    skipped = [r for r in data if r['status'] not in ('ok', 'pending', '')]
    if skipped:
        print('\nnot compared:')
        for r in skipped:
            print('  %-22s %-9s %s' % (r['id'], r['status'], r['note']))

    print('\nn is small until this has run for a while; the benchmark needed n=5 before a prose\n'
          'median stopped lying, and n=37 per arm before the project round could rank anything.')


if __name__ == '__main__':
    main()
