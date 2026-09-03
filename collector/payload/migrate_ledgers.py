"""Add the multi-install columns to both ledgers, padding the rows that predate them.

Run once. It is idempotent: a ledger that already carries the columns is left alone.

Why pad instead of dropping: every existing row is a real measurement and the values being
added are known, not guessed. Until 2026-09-02 exactly one install wrote here - a single
profile on this machine, which has run Lea alone since 2026-08-30 (plugins uninstalled, one
SessionStart hook). So `user`, `host` and `lea_config` are recoverable facts for those rows,
and the whole point of the columns is that from now on nothing has to be recovered.

    python shadow/migrate_ledgers.py [--user <name>] [--host <name>] [--dry-run]
"""
import argparse
import csv
import io
import os
import shutil
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))

LEDGERS = {
    'shadow.csv': ['user', 'host', 'tree_root'],
    'lea.csv': ['user', 'host', 'lea_config'],
}


def migrate(path, new_cols, values, dry):
    if not os.path.exists(path):
        return f'{os.path.basename(path)}: not present, nothing to do'
    with io.open(path, encoding='utf-8-sig', newline='') as fh:
        rows = list(csv.reader(fh))
    if not rows:
        return f'{os.path.basename(path)}: empty'
    header = rows[0]
    missing = [c for c in new_cols if c not in header]
    if not missing:
        return f'{os.path.basename(path)}: already has {", ".join(new_cols)} - unchanged'

    stamp = datetime.now().strftime('%Y%m%d-%H%M%S')
    backup = f'{path}.pre-multiuser-{stamp}'
    out = [header + missing]
    for r in rows[1:]:
        # A short row is a row written before a column existed; pad to the old width first so the
        # new values land in the new columns and not in the middle of someone else's data.
        r = r + [''] * (len(header) - len(r))
        out.append(r[:len(header)] + [values[c] for c in missing])

    if dry:
        return (f'{os.path.basename(path)}: would add {missing} to {len(rows) - 1} rows '
                f'(backup {os.path.basename(backup)})')
    shutil.copy2(path, backup)
    with io.open(path, 'w', encoding='utf-8', newline='') as fh:
        csv.writer(fh, lineterminator='\n').writerows(out)
    return (f'{os.path.basename(path)}: added {", ".join(missing)} to {len(rows) - 1} rows '
            f'-> backup {os.path.basename(backup)}')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--user', default=os.environ.get('USERNAME', ''))
    ap.add_argument('--host', default=os.environ.get('COMPUTERNAME', ''))
    ap.add_argument('--lea-config', default='lea')
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()
    # tree_root is left blank on old rows rather than back-filled with the cwd: before the column
    # existed the runner refused any tree it could not copy, so an old row's root was always its
    # own cwd - but writing that in would be asserting it, and a blank says "not recorded", which
    # is what it is. report.py treats a blank as "same root", the only reading it can have.
    vals = {'user': a.user, 'host': a.host, 'lea_config': a.lea_config, 'tree_root': ''}
    for name, cols in LEDGERS.items():
        print(migrate(os.path.join(HERE, name), cols, vals, a.dry_run))


if __name__ == '__main__':
    main()
