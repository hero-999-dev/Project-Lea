# INSTALL — instructions for a Claude Code session

> Point your own Claude Code session at this file (`read INSTALL.md and set this up for me`)
> and it can perform the whole installation. A human can follow the same steps by hand.
>
> Türkçe: [`INSTALL.tr.md`](INSTALL.tr.md)

**Read this whole file before running anything.** Step 0 is a decision, not a command.

---

## Step 0 — Decide what you actually want

This setup has three independent parts. They are not equally worth installing, and the
benchmark data in [`guide/benchmarks.en.md`](guide/benchmarks.en.md) says so:

| Part | Install it if | Skip it if |
|---|---|---|
| `superpowers` plugin | you do multi-step coding work in the CLI | you only use short chat prompts |
| `verification-activate.js` hook | you have been burned by a confident wrong "done" | you want the cheapest possible sessions |
| `caveman` + `ponytail` plugins | most of your usage is long-form prose/explanations | most of your usage is agentic coding — they measured **0/5** correct on a hard bug fix |
| `lean-context` hook + skill | you have `markitdown`, `trafilatura`, `duckdb`, `repomix` installed | you do not — the hook exits silently, but the skill's advice would be useless |

Ask the user which of these they want before editing anything. The default recommendation
for a coding-heavy user is: **superpowers + the verification hook, without caveman/ponytail.**

---

## Step 1 — Prerequisites

```bash
claude --version   # Claude Code CLI must be installed
node --version     # the two hooks are Node scripts
```

If `node` is missing, install Node.js first or skip the hooks entirely (steps 4–5).

---

## Step 2 — Back up the existing settings

Never edit `settings.json` without a copy of the original.

**macOS / Linux**
```bash
cp ~/.claude/settings.json ~/.claude/settings.json.bak 2>/dev/null || echo "no existing settings.json"
```

**Windows PowerShell**
```powershell
Copy-Item "$env:USERPROFILE\.claude\settings.json" "$env:USERPROFILE\.claude\settings.json.bak" -ErrorAction SilentlyContinue
```

---

## Step 3 — Merge the config

Open [`config/settings.json`](config/settings.json) and merge it into `~/.claude/settings.json`.

**Merge, do not overwrite.** The target file may already contain `permissions`, `model`,
`statusLine`, MCP config, or other hooks that must survive.

Then, in the merged file:

1. Delete the `_comment` key.
2. Replace every `ABSOLUTE_PATH_TO_HOME` with the real home directory. Hook `command` strings
   are **not** shell-expanded — `~`, `$HOME`, and `%USERPROFILE%` do not work there. Use a
   literal path, e.g. `/home/alice` or `C:/Users/alice`.
3. If you decided against `caveman`/`ponytail` in step 0, set both to `false` in
   `enabledPlugins` and delete their `extraKnownMarketplaces` entries.
4. If you are not installing the four converter CLIs, delete the `permissions` block and the
   `skillOverrides` block.
5. `"model": "opus"` is a preference — change or remove it.

---

## Step 4 — Copy the hooks

Copy the contents of [`config/hooks/`](config/hooks/) into `~/.claude/hooks/`.

**macOS / Linux**
```bash
mkdir -p ~/.claude/hooks
cp config/hooks/*.js ~/.claude/hooks/
```

**Windows PowerShell**
```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.claude\hooks" | Out-Null
Copy-Item config\hooks\*.js "$env:USERPROFILE\.claude\hooks\"
```

Skip this step if you declined both hooks — and if you skip it, also delete the `hooks`
block you merged in step 3, or every session will start by failing to find the scripts.

---

## Step 5 — Copy the `lean-context` skill (only if you took that hook)

**macOS / Linux**
```bash
mkdir -p ~/.claude/skills/lean-context
cp config/skills/lean-context/SKILL.md ~/.claude/skills/lean-context/
```

**Windows PowerShell**
```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.claude\skills\lean-context" | Out-Null
Copy-Item config\skills\lean-context\SKILL.md "$env:USERPROFILE\.claude\skills\lean-context\"
```

`lean-context-activate.js` reads this file at every session start. Without it the hook exits
0 silently and nothing breaks.

---

## Step 6 — Restart the CLI

Plugin enable/disable and `SessionStart` hooks only take effect on a fresh process. A
disabled plugin's hooks keep running until then.

The first start after this will be slower: the CLI fetches and caches each plugin under
`~/.claude/plugins/cache/`.

---

## Step 7 — Verify (do not skip)

```bash
claude plugin list
```

Expected: the plugins you chose show `✔ enabled`, the rest `✘ disabled`.

Then start a session and confirm:

1. The hook banners appear at the top of the session context — `VERIFICATION-BEFORE-COMPLETION
   ACTIVE` and/or `LEAN-CONTEXT ACTIVE`.
2. The agent roster does **not** list `caveman:AGENTS` or `caveman:CLAUDE` (see troubleshooting).
3. `/skills` lists the skills you expect.

If the modes did not activate, go to troubleshooting — do not just re-run the install.

---

## Troubleshooting

**Nothing activated. No hook banner, no caveman, no ponytail.**
`SessionStart` hooks share one timeout window: when it expires the entire batch is cancelled
and no hook output is injected at all — so one slow hook silently kills every other one.
Grep the session transcript at `~/.claude/projects/<slug>/<session-id>.jsonl` for
`hook_cancelled` versus `hook_success`. Never put a PowerShell script in a `SessionStart`
hook; `powershell.exe` cold start alone is ~2–3 s. Node starts in ~200 ms.

**`claude plugin list` omits a plugin whose skills clearly load.**
`enabledPlugins` in `settings.json` has desynced from
`~/.claude/plugins/installed_plugins.json`. Fix with
`claude plugin install <plugin>@<marketplace> -y`.

**A plugin is installed but behaves like an old version.**
A stray `~/.claude/skills/<name>/SKILL.md` from an older manual install shadows the plugin
copy. `diff` it against
`~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/skills/<name>/SKILL.md` and delete
or overwrite the loose one.

**Phantom `caveman:AGENTS` / `caveman:CLAUDE` agents in the roster, spawnable with all tools.**
Those are the plugin's contributor docs being read as agent definitions. Rename them:

```bash
cd ~/.claude/plugins/cache/caveman/caveman/*/agents/
mv AGENTS.md AGENTS.doc.txt
mv CLAUDE.md CLAUDE.doc.txt
```

This is a cache edit — a plugin update restores the files, so re-check after each update.

**`skillOverrides` has no effect.**
It cannot hide plugin skills; the resolver short-circuits plugin-sourced skills to `"on"`
before the setting is consulted. It only works on your own skills under `~/.claude/skills/`.
The only lever on a plugin skill is disabling the whole plugin.

**Scripted `claude -p` runs come back as prose with every tool call denied (Windows).**
`claude` on `PATH` may be a `claude.cmd` batch shim; `cmd.exe` truncates the command line at
the first newline inside an argument, so a multi-line `-p` prompt silently drops every flag
after it. Call `<home>/.local/bin/claude.exe` directly from scripts.

---

## Uninstall

```bash
# restore the backup from step 2
cp ~/.claude/settings.json.bak ~/.claude/settings.json
rm ~/.claude/hooks/verification-activate.js ~/.claude/hooks/lean-context-activate.js
rm -rf ~/.claude/skills/lean-context
```

Then restart the CLI.

---

## Full documentation

- [`guide/setup-guide.en.md`](guide/setup-guide.en.md) — what each part does, and why each
  disabled plugin was disabled
- [`guide/benchmarks.en.md`](guide/benchmarks.en.md) — the four measured rounds behind the
  recommendations
