# -*- coding: utf-8 -*-
"""Choose which stock config the shadow arm should run for a given prompt.

The rule comes from the benchmark, not from taste:

  * Prose with no tool use - explain, compare, summarise - is the one round where the terse
    pair wins outright: `modes` 0.096 median against `bare` 0.175 on Sonnet (-45%), and
    0.352 against 0.549 on Opus. So a prose prompt gets `modes`.
  * Every agentic round measured on Sonnet is cheapest on `bare`: easy fix, hard fix, hard
    fix #2, website build. So a prompt that will touch files or run commands gets `bare`.
  * Everything else gets `bare`, because that is the instruction where there is no data - and
    because on the one round with no separation at all (the real project) the four
    non-superpowers configs sit inside a 16% band, well under that round's noise floor.

Turkish is matched with the diacritics stripped and on stems rather than whole words, because
people type "aciklar misin" as often as "açıklar mısın" and the language agglutinates: "fark",
"farkı", "farkları" are one question. Matching whole accented words missed all of that.

A third field says whether the prompt needs the working directory at all. A prose question is
answered in the reply, so the shadow arm can answer it anywhere - which is what lets a session
started outside a project still contribute prose-round data. An agentic prompt needs the tree,
because the tree is the experiment.

Usage:  python pick.py "<prompt text>"    ->  prints "<config>\t<rule>\t<tree|notree>"
"""
import re
import sys

FOLD = {'ı': 'i', 'İ': 'i', 'ş': 's', 'Ş': 's', 'ğ': 'g', 'Ğ': 'g',
        'ü': 'u', 'Ü': 'u', 'ö': 'o', 'Ö': 'o', 'ç': 'c', 'Ç': 'c'}


def fold(text):
    return ''.join(FOLD.get(ch, ch) for ch in text).lower()


# Wanting something built, changed, run or found: the agentic rounds, where bare wins.
AGENTIC = re.compile(
    r'\b(fix|debug|implement|refactor|add|remove|delete|rename|write|create|build|run|test|'
    r'install|deploy|commit|push|merge|update|patch|migrate|generate|screenshot|'
    # Short stems were a trap: `ac` matched "aciklar" (explain) and `kur` matched "kural"
    # (rule), so a prose question read as agentic. Every stem here is long enough to be a verb.
    r'yaz|ekle|sil|duzelt|calistir|kostur|derle|tasi|guncelle|olustur|kaldir|degistir|'
    r'dene|indir|uygula|kapat|baslat|durdur|temizle|tasarla|gelistir|kurar|kurul|kursana)',
    re.I | re.U)

# Wanting an answer in the reply: the prose round, where modes wins.
PROSE = re.compile(
    r'\b(explain|why|what|how does|compare|summari[sz]e|describe|difference|opinion|review|'
    r'should i|which|pros and cons|'
    r'acikla|neden|nedir|nasil|karsilastir|ozetle|fark|gorus|hangisi|anlat|yorumla|'
    # The Turkish question particle is a strong prose signal on its own.
    r'ne dusun|onerin|tavsiye|avantaj|dezavantaj|anlami|misin|musun|misiniz|mudur|midir)',
    re.I | re.U)

# Anything naming a file, a path or a command is agentic whatever else it says.
FILEISH = re.compile(r'[\w\-/\\]+\.(py|js|mjs|ts|tsx|jsx|html|css|json|md|ps1|sh|yml|yaml|csv|'
                     r'txt|toml|ini|xml|sql)\b|(^|\s)(git|npm|node|python|pwsh|bash|cd|ls)\s',
                     re.I)


def pick(prompt):
    """Return (config, rule, needs_tree). The rule is recorded so a later reader can audit it."""
    raw = (prompt or '').strip()
    if not raw:
        return 'bare', 'empty prompt -> no data -> bare', True
    text = fold(raw)
    if FILEISH.search(text):
        return 'bare', 'names a file or command -> agentic -> bare (cheapest on all four tool rounds)', True
    agentic, prose = bool(AGENTIC.search(text)), bool(PROSE.search(text))
    if agentic and not prose:
        return 'bare', 'agentic verb -> bare (cheapest on all four tool rounds)', True
    if prose and not agentic:
        # Answered in the reply, so no directory is involved on either side of the comparison.
        return 'modes', 'prose question, no tool intent -> modes (-45% on the prose round)', False
    if prose and agentic:
        # Mixed intent ends up doing tool work, and the prose saving does not survive it.
        return 'bare', 'mixed prose and agentic -> the work decides -> bare', True
    return 'bare', 'unclassified -> no data -> bare', True


if __name__ == '__main__':
    cfg, rule, tree = pick(' '.join(sys.argv[1:]))
    sys.stdout.write('%s\t%s\t%s\n' % (cfg, rule, 'tree' if tree else 'notree'))
