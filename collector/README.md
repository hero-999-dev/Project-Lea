# Lea collector

Run Lea. Every prompt you answer gets answered a second time in the background, in a copy of
your working directory, by a stock Claude Code configuration. What the two cost — and, if you
choose, what each one changed — is written to a local ledger. You send the ledger back; the
Lea ruleset gets developed from it somewhere else.

You are not asked to develop anything. Install it, work normally, run one command when you
feel like it.

**Türkçe:** [README.tr.md](README.tr.md)

---

## What it will cost you

A second agent run per prompt is real money and real usage. The defaults keep it to a share:

| cap | default | what it does |
|---|---|---|
| per rolling 5 hours | $3 | the shadow arm never takes more than a slice of your window |
| per model, same window | $2 opus / $1 sonnet | one model cannot starve the other's data |
| per day | $6 | backstop |
| per run | $3 | a task bigger than this is recorded as `truncated`, never compared |

It also stands down for an hour after any usage limit, queues prompts it cannot afford yet, and
runs at most one shadow at a time. All of it is in `~/.claude/shadow/config.json`; change any
number, or set `"enabled": false` to stop entirely.

## What it touches

```
~/.claude/hooks/          shadow-enqueue.js, shadow-collect.js, shadow-hidden-launch.vbs, lea.js
~/.claude/shadow/         the runner, the picker, the report, the ledgers, the run copies
~/.claude/shadow-dir.txt  one line, so the hooks can find that directory
~/.claude/settings.json   three hook entries, merged - backed up first
```

Nothing else. Your working directory is never written to: the shadow agent only ever runs
inside `~/.claude/shadow/runs/<id>/work/`, a copy. **Nothing is uploaded.** Data leaves your
machine only when you run `export.ps1` and send the file yourself.

## Requirements

PowerShell 7 (`pwsh`), Node, Python, git, and the Claude Code CLI. The installer checks and
names anything missing.

## Install

```powershell
git clone https://github.com/hero-999-dev/Project-Lea.git
cd Project-Lea\collector
pwsh -NoProfile -File install.ps1
```

Then restart Claude Code. The session banner should start with `LEA ACTIVE`.

If you already run your own `SessionStart` hook and want to keep it, add `-SkipLea` — but read
the note in the script first: the comparison is *Lea against a stock config*, so without Lea the
ledger measures something else.

## Working with it

Work normally. Two things change what gets collected:

- **Work from a project directory.** A prompt sent from your home directory is skipped: the
  home tree is too large to copy and contains `.claude`, your keys and your credentials.
- **Questions are collected anywhere.** A prompt answered in the reply ("what's the difference
  between X and Y") needs no directory, so those are collected even from a home-directory
  session.

Every skip is written to the ledger with its reason. Nothing is silently dropped.

## See what you have

```powershell
python "$env:USERPROFILE\.claude\shadow\report.py"
```

One line per prompt: what Lea's turn cost, what the stock arm cost, which config it picked and
why, and the ratio. Read it before you send anything.

## Send it back

```powershell
pwsh -NoProfile -File "$env:USERPROFILE\.claude\shadow\export.ps1"
```

Writes `lea-shadow-<machine>-<user>-<date>.zip` to your Desktop containing the two ledgers, the
prompts you typed, and a manifest saying which model and budgets produced them.

**It does not include your code.** The diffs — what Lea changed and what the stock config
changed — are what make a *quality* comparison possible rather than a cost-only one, but they
are your source. If you want to include them:

```powershell
pwsh -NoProfile -File "$env:USERPROFILE\.claude\shadow\export.ps1" -IncludePatches
```

`-Since 2026-09-01` limits either form to recent runs. Open the zip and read it before sending;
it is plain CSV and JSON.

## Stop or remove it

Stop collecting, keep everything: set `"enabled": false` in `~/.claude/shadow/config.json`.

Remove it: delete the three hook entries from `~/.claude/settings.json` (a dated backup sits
next to it), then delete `~/.claude/shadow/`, `~/.claude/shadow-dir.txt`, and the three
`shadow-*` files in `~/.claude/hooks/`.

## What happens to it

Ledgers from every machine are pooled, each row tagged with the machine and user it came from —
without that tag the pool is unreadable, since model and budgets differ per install. The pooled
data says where Lea spends more than a stock config and where it earns it. When a change to the
ruleset is proposed, it is measured the way everything else here was: both versions, same day,
same task, twenty samples each. A proposal that does not survive that does not ship.
