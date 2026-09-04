---
name: lea
description: Work on the Lea ruleset and its measurement rig - develop or optimise Lea, propose a v9, read the shadow-arm report, switch a session between the Lea and stock arms, refresh the savings pages, or export a machine's ledger. Use whenever the user says "Lea'yı optimize edelim", "Lea'yı geliştirelim", "lea raporu", "which arm am I on", or otherwise asks to continue the Lea work - from any directory, on any machine.
---

# Lea

Lea is a ~180-token `SessionStart` hook that replaced an 11-plugin configuration, chosen by a
286-run benchmark. Beside it runs a measurement rig. This skill exists so that a session opened
**anywhere** can pick that work up, because nothing else carries it: Claude Code's memory is
scoped per working directory, so notes written in one project are invisible in the next.

## First, find out where you are

Do this before anything else. Do not guess a path, and never hardcode one - this file ships to
other machines and other user profiles.

```powershell
# The pointer every install writes. Its parent is the project root when Lea was installed
# in-project, and ~/.claude when it was installed by the collector.
Get-Content "$HOME\.claude\shadow-dir.txt" -Raw
```

Three cases, and they need different work:

| What you find | Where you are | What "optimise Lea" means here |
|---|---|---|
| the pointer's parent has `savings.py`, `NEXT.md`, `PRENSIPLER.md` | **the lab** - full project | everything below |
| the pointer exists, parent has no `savings.py` | **a collector install** | read the report, switch arms, export the ledger; the ruleset itself is not decided here |
| no pointer at all | **nothing installed** | offer to install: `Project-Lea/collector/install.ps1`, from the drive at `<drive>:\_hub\lea\` or `git clone https://github.com/hero-999-dev/Project-Lea.git` (public, no auth) |

## In the lab

Read these two first, in this order. They are the handover, and they are current:

1. **`NEXT.md`** - what changed last round, how each piece was verified, and the ordered backlog.
2. **`PRENSIPLER.md`** - nine rules, each one written from a mistake that actually happened.
   Rule 1 (a change is not finished when the code is) and rule 9 (everything that leaves this
   machine is assumed lost) are the two that get broken most.

Then look at where the measurement stands:

```powershell
python shadow\report.py        # both arms, the pairs, and what each arm changed on disk
python shadow\arm.py           # which arm the next session will run as
```

**Every round ends with these three, and the round is not finished until all three are clean:**

```powershell
python savings.py          # banner + the two generated report pages + savings.json
python sync_payload.py     # live files -> collector payload and the published copies
python check_docs.py       # secret, leak, shipped, link, numbers, page, stale, mention
```

## What the numbers mean, so you do not overclaim

- The savings headline is a **projection**: a measured ratio from the benchmark times measured
  spend. It is not a measured saving, and the pages say so.
- The **paired** shadow arm can only see prompts that opened their session - 4.3% of spend on the
  account where this was measured. Replaying a conversation into the stock arm would fix that and
  costs $39.76 at the median turn, $206 at the 90th percentile, against a $4 cap. It is a price
  wall, not an oversight.
- The **wide** arm is session-level A/B on the same ledger: `python shadow/arm.py stok`, restart
  the CLI, work normally. 100% coverage, no extra spend, and *not* paired - two sessions are
  different work, so never report it as a paired result.
- 70% of real spend is re-reading the conversation, 12% is output. A proposal that only shortens
  Lea's replies is aiming at the small number; **turn count** is the lever.

## Before proposing a v9

Do not. Not until there is evidence, and evidence means one of two things: enough pairs that can
carry a ratio (the statusline shows `cift N/20`), or a benchmark round - fixed tasks, hidden
tests, n=20 per arm, both arms the same day. That is how v8 was decided: rewriting one paragraph,
the exception clause from permission to obligation, moved the hard round from 4/20 to 13/20.

While Lea is the thing being measured, what must not change is **the banner it emits** -
that is the whole independent variable, and the file around it is not. Checked on
2026-09-04: the live `~/.claude/hooks/lea.js` and the measured `bench/hooks/lea-v8.js`
differ by 43 lines, every one of them a comment, and emit the same 226 words. So compare
output, not files - the rule used to say byte-identical, which was already false and would
have sent someone to "fix" a difference that changes nothing.

A candidate is a candidate only if its banner differs from v8 in ONE paragraph and nothing
else. The three v9 candidates were verified that way: paragraph 5 of 6, +25 / +12 / +29
words, same six paragraphs.

## Things that will bite you

- **Hooks are read at session start.** Anything you change in `settings.json` - including the arm
  switch - does not apply until the CLI is restarted, and the current session keeps recording
  under the old label.
- **Passwords live in one file on the machine that owns them**, outside every repository, and
  never on the drive. `check_docs.py`'s `secret` pass fails the build if one leaks.
- **The repository is public.** So is `pixel-pomo-web`. The report site's password gate stops a
  link from being casually shared and nothing more; nothing that matters if it is read goes
  behind it.
