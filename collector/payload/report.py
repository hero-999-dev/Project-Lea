# -*- coding: utf-8 -*-
"""Join the two ledgers and say what the shadow arm has learned so far.

lea.csv is written by the Stop hook (what Lea's turn cost), shadow.csv by the shadow runner
(what a stock config cost on the same prompt, from the same starting directory). They are
separate files on purpose: two processes, no shared write.

The comparison is a ratio, not a like-for-like dollar figure - Lea runs on whatever model the
session uses and the shadow arm on the model named in config.json. Read "Lea / shadow" as the
price of this session's config against the stock one, and read a same-model row as literal.

Usage:  python report.py            print the table
        python report.py --html     also write shadow-report.html next to it
"""
import csv
import io
import os
import statistics as st
import sys

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


def rows():
    lea, shadow = load('lea.csv'), load('shadow.csv')
    for rid in sorted(set(lea) | set(shadow)):
        l, s = lea.get(rid, {}), shadow.get(rid, {})
        prompt = ''
        pf = os.path.join(HERE, 'runs', rid, 'prompt.txt')
        if os.path.exists(pf):
            prompt = ' '.join(io.open(pf, encoding='utf-8').read().split())[:70]
        yield dict(id=rid, prompt=prompt,
                   when=(l.get('when') or s.get('when') or ''),
                   model=l.get('model', ''), lea=num(l, 'cost_usd'),
                   config=s.get('config', ''), rule=s.get('rule', ''),
                   status=s.get('status', 'pending'), shadow=num(s, 'cost_usd'),
                   lea_turns=num(l, 'turns'), shadow_turns=num(s, 'turns'),
                   note=s.get('note', ''))


def main():
    data = list(rows())
    if not data:
        print('no shadow runs recorded yet')
        return
    print('%-21s %-9s %-9s %-9s %-7s %s' % ('when', 'lea $', 'shadow $', 'config', 'ratio', 'prompt'))
    pairs = []
    for r in data:
        ratio = ''
        # Only a completed shadow run is a measurement. A truncated one has a cost and no result,
        # and comparing it would read as "the stock config was cheaper" when it simply stopped.
        if r['lea'] and r['shadow'] and r['status'] == 'ok':
            ratio = '%.2fx' % (r['lea'] / r['shadow'])
            pairs.append(r['lea'] / r['shadow'])
        print('%-21s %-9s %-9s %-9s %-7s %s' % (
            r['when'][:19],
            '%.4f' % r['lea'] if r['lea'] is not None else '—',
            '%.4f' % r['shadow'] if r['shadow'] is not None else (r['status'] or '—'),
            r['config'] or '—', ratio, r['prompt']))
    print()
    print('%d prompt(s) recorded, %d comparable' % (len(data), len(pairs)))
    if pairs:
        print('Lea / stock cost ratio: median %.2fx, mean %.2fx  (below 1.00 means Lea was cheaper)'
              % (st.median(pairs), st.mean(pairs)))
        ok = [r for r in data if r['lea'] and r['shadow'] and r['status'] == 'ok']
        lea_sum = sum(r['lea'] for r in ok)
        sh_sum = sum(r['shadow'] for r in ok)
        print('totals over comparable prompts: Lea $%.4f, stock $%.4f' % (lea_sum, sh_sum))
    cut = [r for r in data if r['status'] == 'truncated']
    if cut:
        print()
        print('%d run(s) hit the per-run cap and were left out of the comparison. Those prompts '
              'cost more than' % len(cut))
        print('the shadow budget allows; raise budget_usd_per_run and the purses to include them.')
    skipped = [r for r in data if r['status'] not in ('ok', 'pending', '')]
    if skipped:
        print('\nnot compared:')
        for r in skipped:
            print('  %-16s %-9s %s' % (r['id'], r['status'], r['note']))
    print('\nn is small until this has run for a while; the benchmark needed n=5 before a prose\n'
          'median stopped lying, and n=37 per arm before the project round could rank anything.')


if __name__ == '__main__':
    main()
