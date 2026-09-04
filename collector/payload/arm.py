"""Choose which arm the next session runs as: Lea, or the stock config it is measured against.

    python shadow/arm.py            # which arm is armed right now
    python shadow/arm.py lea        # next session runs with Lea
    python shadow/arm.py stok       # next session runs without it
    python shadow/arm.py --flip     # whichever it is not

WHY THIS EXISTS
---------------
The shadow arm answers each session's opening prompt a second time with a stock config, and that
is the only paired evidence there is. It is also structurally small: only a prompt that opens its
session can be paired, and those are 4.3% of what this account actually spends. Everything after
the first prompt - which is where the work happens, and where 70% of the money goes on re-reading
the conversation - it cannot see at all.

Giving the stock arm the same conversation would fix the coverage and is not affordable: the
median turn here carries 4.0M tokens of conversation, which a fresh run pays for as cache-write,
$39.76 once, $206 at the 90th percentile, against a $4 per-run cap. Measured, not guessed.

So the coverage problem is solved from the other end. The Stop hook already prices EVERY turn and
already records which ruleset produced it (`lea_config`). Run some sessions without Lea and the
same ledger separates the two arms by itself: 100% of prompts, no extra spend, and the sessions
being measured are the real ones rather than their first line.

What it costs instead is cleanliness. Two sessions are not the same task, so this is not a paired
comparison and must never be reported as one - it needs n, and it needs the work to be normalised
per prompt. report.py prints it that way.

WHAT IT CHANGES
---------------
One entry in ~/.claude/settings.json: the SessionStart hook that loads lea.js. Nothing is
deleted - the hook file stays on disk, the entry is moved aside under a key Claude Code ignores,
so switching back is exact rather than reconstructed. The shadow arm's own two hooks are left
alone: the ledger must keep recording whichever arm you are on, or the experiment has one side.
"""
import io
import json
import os
import shutil
import sys
from datetime import datetime

HOME = os.environ.get('USERPROFILE') or os.path.expanduser('~')
SETTINGS = os.path.join(HOME, '.claude', 'settings.json')

# Where a disabled entry is parked, and why it is not in settings.json.
#
# It was, under an unknown top-level key, on the assumption that Claude Code ignores keys it does
# not recognise. It does not: a hook-shaped entry declared anywhere but under "hooks" makes the
# CLI reject the ENTIRE file - "Files with errors are skipped entirely, not just the invalid
# settings" - so parking Lea there took the shadow arm's own two hooks down with it, silently,
# until the next start printed a settings error. Found the first time the switch was used for
# real.
#
# So the entry is parked beside the ledger instead, where this project's state already lives, and
# settings.json is left a valid settings file. Keeping the original object rather than a flag
# still matters: turning Lea back on restores exactly what was there - matcher, timeout,
# statusMessage - instead of a plausible reconstruction.
PARK_KEY = '_leaSessionStartDisabled'      # the old location, migrated on sight


def park_file():
    """Beside the ledger, found through the same pointer every hook uses."""
    try:
        p = io.open(os.path.join(HOME, '.claude', 'shadow-dir.txt'), encoding='utf-8').read().strip()
        if p and os.path.isdir(p):
            return os.path.join(p, 'arm-parked.json')
    except Exception:
        pass
    return os.path.join(HOME, '.claude', 'arm-parked.json')


def read_park(cfg):
    """The parked entry, from the file - or from the old settings key, so an install that was
    switched off by the previous version can still be switched back on."""
    if PARK_KEY in cfg:
        return cfg[PARK_KEY]
    try:
        return json.load(io.open(park_file(), encoding='utf-8-sig'))
    except Exception:
        return None


def write_park(entries):
    path = park_file()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with io.open(path, 'w', encoding='utf-8') as fh:
        json.dump(entries, fh, indent=2, ensure_ascii=False)


def clear_park(cfg):
    cfg.pop(PARK_KEY, None)
    try:
        os.remove(park_file())
    except OSError:
        pass


def load():
    with io.open(SETTINGS, encoding='utf-8-sig') as fh:
        return json.load(fh)


def save(cfg):
    # One backup per change, and the name has to prove it. Seconds alone do not: the test flipped
    # the arm five times inside one second and four of the five backups overwrote each other, so
    # a suffix runs until the name is free. A backup that silently is not there is worse than no
    # backup, because it is the thing you reach for after a bad write.
    stamp = datetime.now().strftime('%Y%m%d-%H%M%S')
    path = SETTINGS + '.bak-' + stamp
    n = 2
    while os.path.exists(path):
        path = '%s.bak-%s-%d' % (SETTINGS, stamp, n)
        n += 1
    shutil.copy2(SETTINGS, path)
    with io.open(SETTINGS, 'w', encoding='utf-8') as fh:
        json.dump(cfg, fh, indent=2, ensure_ascii=False)
    return path


def entries(cfg):
    return (cfg.get('hooks') or {}).get('SessionStart') or []


def is_lea(cfg):
    """Lea is on when a SessionStart hook actually points at lea.js.

    Read the same way the Stop hook reads it (liveConfig()), so the ledger's `lea_config` column
    and this answer cannot disagree about what was running.
    """
    return 'lea.js' in json.dumps(entries(cfg))


def state(cfg):
    plugins = len([v for v in (cfg.get('enabledPlugins') or {}).values() if v])
    if is_lea(cfg):
        return 'lea' if not plugins else 'lea+%dplugins' % plugins
    return 'other+%dplugins' % plugins if plugins else 'other'


def turn_off(cfg):
    hooks = cfg.setdefault('hooks', {})
    keep, parked = [], []
    for e in entries(cfg):
        (parked if 'lea.js' in json.dumps(e) else keep).append(e)
    if not parked:
        return False
    if keep:
        hooks['SessionStart'] = keep
    else:
        hooks.pop('SessionStart', None)
    write_park(parked)
    cfg.pop(PARK_KEY, None)          # never leave the old shape behind
    return True


def turn_on(cfg):
    parked = read_park(cfg)
    if not parked:
        return False
    hooks = cfg.setdefault('hooks', {})
    hooks['SessionStart'] = list(parked) + [e for e in entries(cfg)
                                            if 'lea.js' not in json.dumps(e)]
    clear_park(cfg)
    return True


def main(argv):
    want = (argv[1].lower() if len(argv) > 1 else '')
    cfg = load()
    now = state(cfg)

    if not want:
        other = 'stok' if now.startswith('lea') else 'lea'
        print('su an: %s' % now)
        print('sonraki oturum bu kolla acilir.\n')
        # The command as it can actually be pasted, from wherever the reader happens to be. A
        # relative `python shadow/arm.py` only works from the project root, and the one place
        # this is read is a session that opened somewhere else.
        print('degistirmek icin, hangi dizinde olursan ol:')
        print('  python "%s" %s' % (os.path.abspath(__file__), other))
        print('\nsonra CLI\'i yeniden baslat - hook\'lar oturum acilisinda okunuyor.')
        return 0

    if want in ('--flip', 'flip'):
        want = 'stok' if now.startswith('lea') else 'lea'

    if want in ('lea', 'on', 'ac'):
        if now.startswith('lea'):
            print('zaten lea')
            return 0
        if not turn_on(cfg):
            print('geri konacak bir kayit yok - lea.js hook girdisi hic parkta degil.\n'
                  'Kurulumu calistir: pwsh -File Project-Lea\\collector\\install.ps1')
            return 1
    elif want in ('stok', 'stock', 'off', 'kapat'):
        if not now.startswith('lea'):
            print('zaten stok: %s' % now)
            return 0
        if not turn_off(cfg):
            print('kapatilacak bir lea.js girdisi bulunamadi')
            return 1
    else:
        print(__doc__)
        return 2

    backup = save(cfg)
    after = state(load())
    print('%s -> %s' % (now, after))
    print('yedek: %s' % os.path.basename(backup))
    print('\nHook\'lar oturum acilisinda okunuyor: CLI\'i yeniden baslat, yoksa bu oturum hala '
          '%s olarak kaydeder.' % now)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
