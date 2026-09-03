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
~/.claude/settings.json   three hook entries + autoContinueAtUsageLimit, merged - backed up first
```

Nothing else. Your working directory is never written to: the shadow agent only ever runs
inside `~/.claude/shadow/runs/<id>/work/`, a copy. **Nothing is uploaded.** Data leaves your
machine only when you run `export.ps1` and send the file yourself.

### The one behaviour toggle it sets, and why

`autoContinueAtUsageLimit` is the only setting the installer changes that is not a hook. The
CLI's own description of it: *"When a claude.ai usage limit stops your session, wait for the
limit to reset and continue the task automatically. When off, the limit dialog offers the wait
as a choice instead."* It is on by default here because a session that ends at the 5-hour limit
loses that prompt's measurement rather than delaying it — the shadow arm's row is already
written and Lea's turn never is, so the pair ends up half-recorded. The session has to stay
open, and it can still pause for permission prompts. `-NoAutoContinue` leaves it alone.

**Lower-priority mode is a different thing and cannot be pre-set.** The client is *offered* it
in the rate-limit response headers, so it exists only once a limit has actually been hit; there
is no flag, no environment variable and no settings key for it, and nothing to type before the
offer appears. Accept it from the limit dialog, or reopen the menu with `/rate-limit-options`.
None of this reaches the shadow arm, which is headless: its equivalent is the deferral queue and
the stand-down after a limited run, both already in `config.json`.

## Several installs on one Anthropic account

Machines and Windows users each get their own `~/.claude`, so the installs never collide - but
if they sign in to the **same Anthropic account**, they spend the same usage window. The budgets
in `config.json` are per install and know nothing about each other, so N installs can take N
times the intended share of one window.

Divide before you deploy — `-InstallsOnThisAccount <n>` does it for you, dividing
`window_budget_usd`, `daily_budget_usd` and the per-model purses by n. (`budget_usd_per_run` is
deliberately not divided: a single run's ceiling is what keeps a real task from being cut off
mid-work, and a truncated run is a wasted one, not a cheap one.) The report still fills up, just
more slowly, and your own sessions keep the rest of the window.

A second Windows user on the same machine needs the Claude Code CLI installed **for that user** -
one user's profile is not readable by another. The installer checks for it and names it if it is
missing.

### Four installs, two accounts - what to type

Label each install with the account it signs in with, and say how many installs share that
account. The installer divides the budgets for you and writes the label into every export, so
the pooled data can tell rows that competed for one window from rows that did not.

```powershell
# machine 1, user 1  and  machine 2, user 1   -> account A
pwsh -File install.ps1 -Account A -InstallsOnThisAccount 2

# machine 1, user 2  and  machine 2, user 2   -> account B
pwsh -File install.ps1 -Account B -InstallsOnThisAccount 2
```

Each of the four then runs on window $3 / day $5 / opus $2 / sonnet $1 / haiku $0.50 — the
template's $6 / $10 / $4 / $2 / $1 halved, two installs per account. A measured 5-hour window
holds $15–20 of API-priced tokens, so each account still gives up under a fifth of one.

## Two Windows users on one machine, one ledger

`install.ps1` sets up a machine as one contributor: the shadow directory goes under that
profile's own `~/.claude`, and it refuses to repoint an existing one. That is right for a fresh
machine and wrong when the two profiles are **the same person working on the same project** -
you get two ledgers, and whichever profile you happen to start `claude` in is the only one that
records. Use `install-user.ps1` for the second profile: it joins the first one's ledger instead
of starting a parallel one.

```powershell
# first profile: the normal install, which creates the ledger
pwsh -File install.ps1 -Account A -InstallsOnThisAccount 2

# second profile: join that ledger rather than start another
pwsh -NoProfile -File install-user.ps1 `
     -TargetHome  C:\Users\<second-user> `
     -SharedShadow C:\Users\<first-user>\.claude\shadow
```

Run it from an account that can write into the target profile - an administrator, or that user
themselves. It backs up every file it overwrites, refuses to repoint a `shadow-dir.txt` that
already names a different directory, and checks afterwards that every hook command it wrote
resolves to a file that exists. Add `-WhatIf` to see the plan without touching anything.

**It also switches `enabledPlugins` off in the second profile, and that is the point, not a side
effect.** A session with plugins on is not Lea, so its rows are not Lea's rows. Both ledgers
carry `user`, `host` and `lea_config` for the same reason: with two installs writing one file, a
row that does not say who wrote it under which ruleset cannot be told apart from one written
under a different account, budget or model - and a difference between installs would read as a
difference between configs. `report.py` prints a line per install, and any row whose
`lea_config` is not `lea` is excluded from every Lea claim rather than quietly averaged in.
Pass `-KeepPlugins` only if you mean it.

Both profiles then append to the same two CSVs, so the appends take a lock file
(`.ledger.lock`) that the PowerShell runner and the Node hook both honour. The shared budget
follows for free: the window and daily caps are computed from the shared `shadow.csv`, so two
profiles on one Anthropic account cannot each spend the full share.

An existing single-install ledger gains the new columns with:

```powershell
python shadow/migrate_ledgers.py          # --dry-run first if you want to see it
```

**Where you start `claude` is not a rule you have to remember.** The shadow arm answers inside a
copy of the working directory, so that directory has to be copyable — and a probe decides whether
it is, not a rule. The probe is the copy routine itself, so it can never approve a tree the copy
would refuse, and size alone does not decide: files over `max_file_mb` are skipped before
anything is counted. Against the default caps a project at 885 files / 56 MB fits and so does its
*parent* at 1,649 files / 399 MB, while a home directory generally does not — one hit the 600 MB
cap at 1,473 files, another did not finish the 20 s probe.

When it does not fit, `project_roots` in `config.json` says where to run instead, so the prompt is
measured rather than dropped. Never silently: the row records `tree_root` and `report.py` compares
it against Lea's own working directory, keeping a pair whose arms started from different trees
apart from one whose arms did not. Empty `project_roots` restores the older skip-instead
behaviour. Lea's own side of the ledger records either way.

## Getting the files onto the machine

The repository is private, so the clone needs the same GitHub account:

```powershell
gh auth login          # once per machine or user
gh repo clone hero-999-dev/Project-Lea
```

Or download the ZIP from the repository page while signed in and unpack it - the collector needs
no git history, only the files.

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
