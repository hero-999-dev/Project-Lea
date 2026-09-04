# INSTALL — Lea

> Hand this file to your own Claude Code session (`read INSTALL.md and install Lea for me`) and it
> can do the whole thing. The same steps work by hand.
>
> Türkçe: [`INSTALL.tr.md`](INSTALL.tr.md)

**What gets installed is one file.** No plugins, no marketplace, nothing to download. Lea is a
`SessionStart` hook that loads a ~180-token rule set at the start of every session.

Why this and not the plugins: a 220-run benchmark measured five configurations and none of them won
across every kind of work. Lea was designed from the mechanisms those runs exposed, then measured
against the best rival in each of five test rounds. Numbers in
[`guide/benchmarks.en.md`](guide/benchmarks.en.md) and on the report page.

| test round | Lea | best rival that day | delta |
|---|---|---|---|
| prose, no tools | 0.0626 | `modes` 0.0577 | tie |
| easy bug fix | 0.0828, 3/3 correct | `bare` 0.0957 | −13% |
| hard bug fix | 0.0897, **4/5 correct** | `superpowers` 0.1244, 1/5 | −28%, 4× the correct fixes |
| website build | 0.0757, 7/7 three times | `bare` 0.0911 | −17% |
| hard bug fix #2 | 0.0815, 3/3 correct | `bare` 0.0799 | +2%, a tie |

All Sonnet, 2026-08-25, rivals re-measured the same day.

---

## Step 1 — Prerequisites

```bash
claude --version   # Claude Code CLI must be installed
node --version     # the hook is a Node script
```

If `node` is missing, install Node.js first. Lea has no other dependency.

---

## Step 2 — Back up your settings

```bash
mkdir -p ~/.claude/backups/lea-install
cp ~/.claude/settings.json ~/.claude/backups/lea-install/settings.json
```

On Windows PowerShell:

```powershell
New-Item -ItemType Directory -Force ~\.claude\backups\lea-install | Out-Null
Copy-Item ~\.claude\settings.json ~\.claude\backups\lea-install\settings.json -Force
```

If there is no `settings.json`, skip this — step 4 writes one.

---

## Step 3 — Copy the hook

```bash
mkdir -p ~/.claude/hooks
cp config/hooks/lea.js ~/.claude/hooks/lea.js
node ~/.claude/hooks/lea.js | head -1     # must print "LEA ACTIVE ..."
```

If that last line prints nothing, the hook is broken — stop here.

---

## Step 4 — Add the hook to `settings.json`

**Merge** into your existing `settings.json`, do not overwrite it. If a `SessionStart` block is
already there, add Lea as one more entry in its `hooks` array.

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume|clear|compact",
        "hooks": [
          {
            "type": "command",
            "command": "node \"/home/<user>/.claude/hooks/lea.js\"",
            "timeout": 20
          }
        ]
      }
    ]
  }
}
```

On Windows the command reads (backslashes are doubled inside JSON):

```json
"command": "node \"C:\\Users\\<user>\\.claude\\hooks\\lea.js\""
```

Use the real username. A relative path or `~` will not work.

---

## Step 5 — Restart the CLI

The hook is read at session start only. Running sessions keep the old behaviour.

---

## Step 6 — Verify (do not skip)

Open a new session. The first system context should contain:

```
LEA ACTIVE - always on. Terse prose, unlimited analysis.
```

If it does not: check that `settings.json` is valid JSON, that the path in `command` is absolute,
and that the file is actually there — in that order.

---

## What not to put where this ends up

The shadow arm writes a ledger, one command packages it, and the reports are published — so ask
of anything you add: *what if this file were in a stranger's hands tomorrow?* Three places it can
end up, and none of them can be taken back: a **public repository** (forks and clones outlive a
delete), a **published page** (caches and archives outlive it too), and a **removable drive**
(assume it will be lost).

So, without exception:

- **No passwords, tokens, API keys or recovery codes** in any of the three. Not in a config, not
  in a comment, not "temporarily". `export.ps1` leaves your diffs out by default for the same
  reason — they are your source code.
- **No absolute paths carrying an account name, no machine names.** The ledger records `user` and
  `host` because two installs sharing one file cannot otherwise be told apart, and `export.ps1`
  replaces the machine name with a one-way digest before anything leaves. Published pages use the
  account labels from `shadow/config.json` (`A`, `B`) and never a real name.
- **A password gate is not secrecy.** If you put the reports behind one, it stops a URL from being
  casually shared; it does not stop anyone who reads the repository. Nothing that matters if it is
  read belongs behind it.
- **When in doubt, leave it out.** There is no undo for any of the three.

## What this does not install, and why
This guide installs no plugins. The measurements say Lea does what `caveman`, `ponytail` and
`superpowers` do together, more cheaply on most rounds: those three inject roughly 6,000 tokens of
rules that are re-read on every one of a tool task's 6–9 turns. Lea's rule set is ~180 tokens.

**If they are already installed, do not run Lea alongside them.** The rule sets stack, the
instructions contradict each other, and the measured gain disappears. Set the `caveman`, `ponytail`
and `superpowers` entries under `enabledPlugins` in `~/.claude/settings.json` to `false`, then
restart the CLI.

The two older hooks (`verification-activate.js`, `lean-context-activate.js`) do not conflict with
Lea, but the `hooks` configuration measured more expensive than `bare` on tool work and once cost
4.4× its own median on the website round. Keep them if you want them — Lea's numbers were measured
without them.

This guide installs only Lea's rule set. The shadow arm that measures Lea — it answers every prompt
a second time under a stock configuration and writes both costs to a local ledger — is not part of
it: that arm and its own install scripts are in `collector/`, described in
[`collector/README.md`](collector/README.md).

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| No `LEA ACTIVE` in the session | hook never ran | is `settings.json` valid JSON (`node -e "JSON.parse(require('fs').readFileSync(process.env.HOME+'/.claude/settings.json'))"`), is the path absolute |
| `node: not found` in the hook error | node not on PATH | write node's full path in `command` |
| Answers still long | old session | restart the CLI; hooks do not load mid-session |
| Answers too short, analysis cut too | another terseness rule is active | check that `caveman`/`ponytail` are off — their rules collide with Lea's analysis exception |
| `... hook timed out after 20s` (e.g. `UserPromptSubmit hook timed out after 10s - output discarded`) | the hook did not finish inside the `timeout` on its `settings.json` entry, and its output is dropped — so `LEA ACTIVE` never reaches that session | raise that entry's `timeout` and restart the CLI; Lea's hook only prints a string, so if 20 s is not enough node itself is slow to start — write node's full path in `command`. A `UserPromptSubmit`/`Stop` timeout is a collector hook, not Lea's ([`collector/README.md`](collector/README.md)) |

---

## Uninstall

```bash
cp ~/.claude/backups/lea-install/settings.json ~/.claude/settings.json
rm ~/.claude/hooks/lea.js
```

Then restart the CLI.

---

## Full documentation

- Lea's design, version log and five test results: the report page (`rapor-lea.html`)
- Method and the five-configuration comparison: [`guide/benchmarks.en.md`](guide/benchmarks.en.md)
- The long form of these setup notes: [`guide/setup-guide.en.md`](guide/setup-guide.en.md)
