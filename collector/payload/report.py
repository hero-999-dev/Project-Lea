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


def rows():
    lea, shadow = load('lea.csv'), load('shadow.csv')
    for rid in sorted(set(lea) | set(shadow)):
        l, s = lea.get(rid, {}), shadow.get(rid, {})
        prompt = ''
        pf = os.path.join(HERE, 'runs', rid, 'prompt.txt')
        if os.path.exists(pf):
            prompt = ' '.join(io.open(pf, encoding='utf-8').read().split())[:44]
        yield dict(
            id=rid, prompt=prompt, when=(l.get('when') or s.get('when') or ''),
            model=l.get('model', ''), config=s.get('config', ''), rule=s.get('rule', ''),
            status=s.get('status', 'pending'), note=s.get('note', ''),
            lea_cost=num(l, 'cost_usd'), sh_cost=num(s, 'cost_usd'),
            lea_turns=num(l, 'turns'), sh_turns=num(s, 'turns'),
            lea_out=num(l, 'output_tokens'), sh_out=num(s, 'output_tokens'),
            lea_in=carried(l), sh_in=carried(s),
            depth=num(l, 'turns_before'))


def main():
    data = list(rows())
    if not data:
        print('no shadow runs recorded yet')
        return

    # A pair is one prompt answered twice and finished twice. A truncated shadow run has a cost
    # and no result, and comparing it would read as "the stock config was cheaper" when it
    # simply stopped.
    pairs = [r for r in data if r['status'] == 'ok' and r['lea_turns'] and r['sh_turns']]

    print('%-17s %-7s %13s %15s %17s  %s' %
          ('when', 'config', 'turns L/S', 'output L/S', 'carried in L/S', 'prompt'))
    for r in pairs:
        print('%-17s %-7s %13s %15s %17s  %s' % (
            r['when'][:16], r['config'] or '—',
            '%d / %d' % (r['lea_turns'], r['sh_turns']),
            '%s / %s' % (tok(r['lea_out']), tok(r['sh_out'])),
            '%s / %s' % (tok(r['lea_in']), tok(r['sh_in'])),
            r['prompt']))

    # A pair is a measurement only if both arms were given the same problem, and a prompt sent
    # mid-conversation is not that. "commit et" means something to Lea, which has the session,
    # and nothing to a shadow run starting from an empty context in a copy of the directory:
    # the two arms answer different questions and their turns, output and cost describe
    # different work. Only a prompt that opened its session is safe, and even that is necessary
    # rather than sufficient - one that refers to yesterday still refers to nothing here.
    opening = [r for r in pairs if r['depth'] == 0]
    later = [r for r in pairs if r['depth'] is None or r['depth'] > 0]

    print('\n%d prompt(s) recorded, %d paired, %d of those comparable.'
          % (len(data), len(pairs), len(opening)))
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
        turn_r = [x for x in (ratio(r['lea_turns'], r['sh_turns']) for r in opening) if x]
        out_r = [x for x in (ratio(r['lea_out'], r['sh_out']) for r in opening) if x]
        print('\nWhat the ruleset moves - both arms answered the same prompt from the same')
        print('directory, so these compare directly (below 1.00 means Lea did it with less):')
        if turn_r:
            print('  turns   median %.2fx   %s' % (st.median(turn_r),
                  ' '.join('%.2f' % x for x in turn_r)))
        if out_r:
            print('  output  median %.2fx   %s' % (st.median(out_r),
                  ' '.join('%.2f' % x for x in out_r)))

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
        matched = [r for r in opening if r['lea_in'] and r['sh_in'] and r['lea_in'] <= 2 * r['sh_in']]
        cost_r = [x for x in (ratio(r['lea_cost'], r['sh_cost']) for r in matched) if x]
        print('\nCost ratio, over the pairs where the two arms carried comparable input:')
        if cost_r:
            print('  median %.2fx over %d pair(s)' % (st.median(cost_r), len(cost_r)))
        else:
            missing = sum(1 for r in opening if r['lea_in'] is None or r['sh_in'] is None)
            print('  no comparable pair yet (%d of %d recorded before the ledgers kept the input'
                  ' counts).' % (missing, len(opening)))
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
