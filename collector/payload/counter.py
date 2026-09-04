"""Write the one number the statusline shows: how many pairs can carry a ratio.

    python shadow/counter.py

The statusline renders on every keystroke-ish refresh and this computation takes ~1.7 s, so it
cannot be done there. The Stop hook runs this detached instead, once per turn, and the statusline
only reads the small JSON it leaves behind.

The rule is not restated here. `usable` is report.comparable() filtered by report.work_matched(),
imported from the one place that defines them - the whole reason those two functions were hoisted
to module level was that a second copy of "comparable" would eventually disagree with the first,
and the copy on display is the one nobody thinks to re-check.
"""
import io
import json
import os
import sys
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

OUT = os.path.join(HERE, 'counter.json')

# What the count is being collected towards. Kept in step with savings.PAIRS_NEEDED by reading it
# rather than repeating it; savings.py lives one directory up and is not importable from a hook's
# environment on every machine, so a failure to import falls back to the same literal instead of
# taking the statusline down.
def target():
    try:
        sys.path.insert(0, os.path.dirname(HERE))
        import savings
        return int(savings.PAIRS_NEEDED)
    except Exception:
        return 20


def arms():
    """Priced turns on each side of the wide comparison.

    The paired counter moves once per session at best, and only when a session-opening prompt
    happens to be pairable - so a stock session shows no progress at all on it and looks like
    nothing is being collected, which is exactly the complaint that produced the second arm. This
    is what a stock session actually fills, so it belongs on the statusline beside the other.

    Only an exact `lea` counts as Lea, and only an exact `other*` as stock: a suffixed label
    (`other-carried-lea`, `lea-no-banner`) means the settings and the transcript disagreed, and a
    row nobody can vouch for is reported, never counted. See armLabel() in shadow-collect.js.
    """
    lea = stok = unsure = 0
    try:
        import csv
        with io.open(os.path.join(HERE, 'lea.csv'), encoding='utf-8-sig', newline='') as fh:
            for r in csv.DictReader(fh):
                cfg = (r.get('lea_config') or '').strip()
                if cfg == 'lea':
                    lea += 1
                elif cfg.startswith('other') and '-' not in cfg:
                    stok += 1
                elif cfg:
                    unsure += 1
    except OSError:
        pass
    return lea, stok, unsure


def main():
    import report
    data = list(report.rows())
    comparable = report.comparable(data)
    usable = [r for r in comparable if report.work_matched(r)]
    lea, stok, unsure = arms()
    payload = {
        'usable': len(usable),
        'comparable': len(comparable),
        'needed': target(),
        'rows': len(data),
        'lea_rows': lea,
        'stok_rows': stok,
        'unsure_rows': unsure,
        'generated': datetime.now().strftime('%Y-%m-%d %H:%M'),
    }
    # Written whole, then moved into place: the statusline reads this file constantly, and a
    # half-written JSON would make it throw on a render rather than simply show nothing.
    tmp = OUT + '.tmp'
    with io.open(tmp, 'w', encoding='utf-8') as fh:
        json.dump(payload, fh, ensure_ascii=False)
    os.replace(tmp, OUT)
    return payload


if __name__ == '__main__':
    try:
        print(json.dumps(main(), ensure_ascii=False))
    except Exception as exc:
        # Never a non-zero exit: this is spawned fire-and-forget from a hook, and a failure here
        # must not be able to look like a failure of the turn that spawned it.
        print('counter: %s' % exc, file=sys.stderr)
