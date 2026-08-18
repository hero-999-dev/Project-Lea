# Claude Code CLI — Skill & Plugin Setup

A portable reference for reproducing a tuned Claude Code skill setup on another machine.
Covers what is installed, how it auto-activates, what was deliberately turned off and why,
and the exact config to copy.

> **Revised after a token-cost audit (§5).** The enabled plugin set went from 11 to 3.
> The benchmark data behind that decision is in [`benchmarks.en.md`](benchmarks.en.md).

Paths in this document use `~/.claude`. On Windows that is `%USERPROFILE%\.claude`.

---

## 1. Three layers of "skill"

### A. Built-in — ship with Claude Code itself, need zero setup

Present on any install automatically: `artifact-design`, `artifact-diagramming`,
`artifact-capabilities`, `dataviz`, `claude-api`, `run`, `init`, `security-review`,
`update-config`, `keybindings-help`, `fewer-permission-prompts`, `loop`, `schedule`,
`code-review`, `simplify`.

Note `code-review` and `simplify` in that list — they are **built-in**, and they are the
reason the `code-review` and `code-simplifier` plugins turned out to be redundant (§5).

### B. Official marketplace plugins — source `claude-plugins-official`, already known to the CLI

No marketplace-add step, just enable:

| Plugin | Purpose | State |
|---|---|---|
| `superpowers` | Meta-framework: forces skill-checking discipline every turn, plus process skills (brainstorming, TDD, systematic-debugging, writing/executing plans, code review request/receive, git worktrees) | **enabled** |
| `security-guidance` | Backs the `security-review` skill, and adds per-turn hooks that run their own LLM review | disabled — §5 |
| `code-simplifier` | Agent that simplifies/refines recently-changed code | disabled — duplicates built-in `simplify` |
| `code-review` | `/code-review` command. Note: `ultra` is **not** from this plugin (see §7) | disabled — duplicates the built-in `code-review` skill |
| `skill-creator` | Create, edit, and benchmark custom skills | disabled — duplicates superpowers `writing-skills` |
| `frontend-design` | Visual/UI design guidance for building or reshaping interfaces | disabled — unused |
| `claude-md-management` | Audit/improve `CLAUDE.md` files | disabled — unused |
| `github` | `gh`-backed GitHub workflow helpers | disabled — its MCP server needs an unset env var (§6) |
| `feature-dev` | Guided feature dev (code-architect / code-explorer / code-reviewer agents) | disabled — unused |

### C. Third-party marketplace plugins — need the marketplace registered first

| Plugin | Marketplace repo | Purpose | State |
|---|---|---|---|
| `ponytail` | `github:DietrichGebert/ponytail` | Lazy-senior-dev mode — simplest/shortest working code, YAGNI | **enabled** |
| `caveman` | `github:JuliusBrussee/caveman` | Ultra-compressed terse prose mode | **enabled** |

> Read §5 and the benchmarks before enabling `caveman` and `ponytail` globally. They are a
> large win on prose-heavy work and a measured **loss** on multi-step agentic coding.

---

## 2. Reproduce on a new machine

Merge [`config/settings.json`](../config/settings.json) into `~/.claude/settings.json`,
then restart the CLI:

```json
{
  "enabledPlugins": {
    "superpowers@claude-plugins-official": true,
    "ponytail@ponytail": true,
    "caveman@caveman": true,
    "code-simplifier@claude-plugins-official": false,
    "frontend-design@claude-plugins-official": false,
    "skill-creator@claude-plugins-official": false,
    "security-guidance@claude-plugins-official": false,
    "code-review@claude-plugins-official": false,
    "claude-md-management@claude-plugins-official": false,
    "github@claude-plugins-official": false,
    "feature-dev@claude-plugins-official": false
  },
  "extraKnownMarketplaces": {
    "ponytail": { "source": { "source": "github", "repo": "DietrichGebert/ponytail" } },
    "caveman":  { "source": { "source": "github", "repo": "JuliusBrussee/caveman" } }
  }
}
```

The `false` entries are kept rather than deleted so the decision is recorded and a single
edit re-enables one.

Equivalent explicit route, from inside the CLI:

```
/plugin marketplace add DietrichGebert/ponytail
/plugin marketplace add JuliusBrussee/caveman
/plugin install superpowers@claude-plugins-official
/plugin install ponytail@ponytail
/plugin install caveman@caveman
```

Either way, the CLI fetches and caches each plugin under `~/.claude/plugins/cache/` on
first use.

---

## 3. What activates immediately vs on request

**Auto-active the moment the plugin is enabled.** Each prints its own ruleset into hidden
context via a `SessionStart` hook — no trigger phrase needed:

- `superpowers` → its `using-superpowers` meta-rule ("if a skill might apply, you must invoke it")
- `caveman` → terse mode, default intensity `full`
- `ponytail` → lazy/minimal-code mode, default intensity `full`

Intensity for the latter two persists across sessions in `~/.claude/.caveman-active` and
`~/.claude/.ponytail-active`. `ponytail` also registers a `SubagentStart` hook, so its
rules reach spawned subagents, not just the main thread.

### Two hand-rolled always-on hooks

Neither is part of any plugin. Copy [`config/hooks/`](../config/hooks/) into
`~/.claude/hooks/` and wire them into one `SessionStart` entry:

```json
"hooks": {
  "SessionStart": [{
    "matcher": "startup|resume|clear|compact",
    "hooks": [
      {
        "type": "command",
        "command": "node \"<ABSOLUTE-PATH-TO>/.claude/hooks/verification-activate.js\"",
        "timeout": 20,
        "statusMessage": "Loading verification-before-completion..."
      },
      {
        "type": "command",
        "command": "node \"<ABSOLUTE-PATH-TO>/.claude/hooks/lean-context-activate.js\"",
        "timeout": 20,
        "statusMessage": "Loading lean-context..."
      }
    ]
  }]
}
```

- **`verification-activate.js`** pins `verification-before-completion` always-on; inside
  superpowers it is normally on-demand. It emits its text **inline** — it does not read the
  superpowers `SKILL.md`. That skill file is ~3.6 KB of tables and rationalization lists,
  while the enforceable core (the Iron Law, the gate, the red flags) is ~1 KB. Inlining cut
  the payload 3537 → 1060 characters and dropped two fragile dependencies at once:
  superpowers having to be installed, and having to guess which cache directory is current.
  The full skill is still reachable as `/superpowers:verification-before-completion`.
- **`lean-context-activate.js`** pins a personal `lean-context` skill (route bulky sources
  through `markitdown` / `trafilatura` / `duckdb` / `repomix` instead of reading them raw).
  It *does* read its source, `~/.claude/skills/lean-context/SKILL.md`, so the two stay in
  sync; that file is small enough that inlining would not pay. The skill ships in
  [`config/skills/lean-context/`](../config/skills/lean-context/) — it assumes those four
  CLIs are installed, so drop this hook if they are not.

Both exit 0 silently if their source is missing, so a half-migrated machine degrades
instead of breaking the session.

> Historical note, still relevant to any *new* hook that reaches into `plugins/cache/`:
> sort cached `superpowers/*` directories by **mtime**, not by parsing the directory name.
> Those directories are named by version *or* by commit sha (`b36e0829c6d0`), and a
> `[version]` cast on a sha throws. The duplicate-directory situation is real (§6).

**Everything else is on-request** — invoked by a `/slash-command`, an explicit trigger
phrase, or by the `using-superpowers` meta-rule matching the current task:

- superpowers process skills: `brainstorming`, `systematic-debugging`,
  `test-driven-development`, `writing-plans`, `executing-plans`, `requesting-code-review`,
  `receiving-code-review`, `finishing-a-development-branch`, `subagent-driven-development`,
  `using-git-worktrees`, `dispatching-parallel-agents`, `writing-skills`
- caveman/ponytail extras: `cavecrew` (+ its three subagents), `caveman-explore`,
  `caveman-commit`, `caveman-review`, `ponytail-review`, `ponytail-audit`, `ponytail-debt`,
  and the workflow skills (`surgical-patch`, `safe-refactor`, `lean-build`, `migration`,
  `investigate-first`, `verify-and-stop`)
- built-ins: see §1A

---

## 4. Gotchas that cost real debugging time

- **One slow `SessionStart` hook kills every other one.** `SessionStart` hooks share a
  single timeout window; when it expires the whole batch is cancelled and **no** hook
  output is injected — so a slow custom hook silently takes caveman and ponytail down with
  it, and the session looks like the plugins were never installed. Observed case: a
  PowerShell verification hook took 5738 ms against a 5000 ms budget (the transcript
  recorded `hook_cancelled` / `timedOut: true`), and all three modes went missing.
  `powershell.exe` cold start alone is ~2–3 s on Windows and spikes higher while the plugin
  cache is being written, so **never put PowerShell in a `SessionStart` hook** — Node starts
  in ~200 ms. Diagnose by grepping the session transcript
  (`~/.claude/projects/<slug>/<session-id>.jsonl`) for `hook_cancelled` vs `hook_success`.
  Related: `security-guidance` registers a `SessionStart` hook with `"timeout": 180`, which
  makes it the standing prime suspect for any repeat of this outage.

- **Loose shadow file.** A stray `~/.claude/skills/<name>/SKILL.md` left over from an old
  manual install silently shadows the plugin version even though `settings.json` looks
  correct — the plugin shows as installed but behaves wrong. Fix: `diff` the loose file
  against
  `~/.claude/plugins/cache/<marketplace>/<plugin>/<version-hash>/skills/<name>/SKILL.md`
  and overwrite the loose copy if they differ.

- **Enabled ≠ installed.** `settings.json` can list a plugin under `enabledPlugins` while
  `~/.claude/plugins/installed_plugins.json` has no entry for it — a marketplace refresh
  dropped two plugins from that registry in one observed case. Symptom: `claude plugin list`
  omits the plugin even though its skills still load. Fix:
  `claude plugin install <plugin>@<marketplace> -y` (re-registers, no reconfiguration).
  Cross-check the two files whenever `plugin list` disagrees with what a session can see.

- **A stray `.md` in a plugin's `agents/` directory becomes a phantom agent.** caveman ships
  `agents/AGENTS.md` and `agents/CLAUDE.md` as contributor docs. Having no YAML frontmatter
  does not exclude them — they surface in the agent roster as `caveman:AGENTS` and
  `caveman:CLAUDE`, described only as "Agent from caveman plugin", each spawnable with **All
  tools**. Fix by renaming both to `.doc.txt`. There is no `agentOverrides` setting to do
  this from `settings.json`, so the rename is a cache edit and **an upstream plugin update
  will restore the files** — re-check after any caveman update.

- **Hardcoded paths.** Hook `command` entries in `settings.json` need absolute paths. When
  copying this config to a different account or machine, swap the home-directory segment
  (or use `$HOME` / `%USERPROFILE%`) before pasting the block in §2. Note that the CLI
  binary and the config tree do not have to live under the same user — do not assume one
  implies the other when searching for files.

- **Windows vs POSIX.** Both hand-rolled hooks are Node, so they are already
  cross-platform — no bash rewrite needed on macOS/Linux. The plugins' own hooks (caveman,
  ponytail) ship both a POSIX `command` and a `commandWindows` variant, so those need no
  change either way.

- **Batch-shim argument truncation on Windows.** If `claude` on `PATH` resolves to a
  `claude.cmd` batch shim that forwards with `%*`, `cmd.exe` truncates the command line at
  the first newline inside an argument. A multi-line `-p` prompt therefore silently drops
  every flag after it — `--output-format json` and `--permission-mode bypassPermissions`
  both vanish, and the run comes back as prose with every tool call denied. The symptom
  looks like a permissions bug and is not. Call the real executable
  (`<home>/.local/bin/claude.exe`) directly from scripts.

---

## 5. The token-cost audit

Every enabled plugin costs tokens on **every** session before you type anything: its
`SessionStart` hook output, plus one line per skill and per agent in the listings the model
receives. Measured baseline, in characters:

| Source | Before | After |
|---|---:|---:|
| `SessionStart` injections (5 hooks) | 18,533 | 16,056 |
| Plugin skill listing | 13,322 | 12,280 |
| Plugin agent listing (removed entries) | — | −1,323 |
| **Total** | **31,855** | **~27,013** |

Roughly 1,300 tokens per session, verified.

### Measured startup cost

`claude -p`, Haiku, identical prompt:

| Config | Prompt tokens |
|---|---:|
| no plugins, no custom hooks | 22,651 |
| caveman+ponytail off, superpowers on | 24,842 |
| **3-plugin config (this setup)** | **27,803** |
| old 11-plugin config | 29,137 |

Saved 1,334 tokens/session = 4.6% of the total prompt, 20.6% of the plugin+hook stack.
caveman+ponytail's own fixed input cost is **2,961 tokens/session**.

### How the cuts were chosen

`~/.claude.json` records real usage in `pluginUsage` and `skillUsage`. Across 22 startups,
seven plugins sat at `usageCount: 0` — `code-simplifier`, `frontend-design`,
`skill-creator`, `code-review`, `claude-md-management`, `github`, `feature-dev`. Three of
those duplicated something already present (§1A/§1B "State" column), so disabling them cost
no capability at all. Check the same file before trusting any claim in this document about
what is or isn't used:

```
node -e "const c=require(process.env.USERPROFILE+'/.claude.json'); console.log(c.pluginUsage)"
```

On macOS/Linux:

```
node -e "const c=require(process.env.HOME+'/.claude.json'); console.log(c.pluginUsage)"
```

### `security-guidance` was disabled for cost, not because it misbehaved

Its `hooks.json` fires `security_reminder_hook.py` (111 KB) on *every* `UserPromptSubmit`,
every `PostToolUse` for `Edit|Write|MultiEdit|NotebookEdit`, every `Bash`, and every `Stop` —
the log showed six Python spawns inside one second. Outside a git repo it exits early
(`Stop hook: empty review set`), costing only ~150–300 ms per tool call. **Inside a git repo
the `Stop` hook is `asyncRewake: true` and runs an Agent SDK security review per turn, billed
to the same quota as the session itself.** That is the single largest recurring cost in this
setup. The on-demand replacements are the built-in `/security-review` and `/code-review`.

If you want the plugin's per-edit pattern warnings without the per-turn LLM review, the hooks
live in the plugin's own `hooks/hooks.json` — but editing that is a cache edit and an update
will revert it. `settings.json` hooks are additive, so there is no way to subtract a plugin's
hook from user settings; enable-or-disable is the whole lever.

### `skillOverrides` — what it can and cannot do

Schema, four values, keyed by skill name:

| Value | Effect |
|---|---|
| `"on"` | default when absent |
| `"name-only"` | lists the skill without its description |
| `"user-invocable-only"` | hides it from the model, keeps `/name` typable |
| `"off"` | hides it from both |

`disableBundledSkills` is the separate switch for the skills shipped with Claude Code.

**It does not work on plugin skills — by design.** The resolver reads
`if (e.type !== "prompt" || e.source === "plugin") return "on"`, so a plugin-sourced skill
short-circuits to `"on"` before `skillOverrides` is ever consulted. This is not a key-format
or syntax problem, and no restart fixes it. Confirmed empirically: an attempt with 13 entries
saved **zero** tokens, because 12 of them were plugin skills; the one that worked was a real
user skill under `~/.claude/skills/`. **The only lever on plugin skills is disabling the whole
plugin via `enabledPlugins`.**

`skillOverrides` applies live, not at session start — the listing changes mid-session when
the file is edited.

### The budget cap — why trimming the skill list saves nothing

The whole skill listing costs only ~2,588 tokens and is capped by
`skillListingBudgetFraction` (default 1% of the context window, in characters). When the
listing exceeds the cap, descriptions are shortened to fit — so removing skills does **not**
shrink the total, it just lets the survivors keep longer descriptions. Any future "trim the
skill list to save tokens" plan is therefore wrong; trimming buys triggering accuracy, not
tokens.

Useful side finding: the `/skills` UI reports a per-plugin **"Skill-listing footprint …
~N tok/turn"**, so the per-plugin listing cost can be read off directly instead of estimated.

### Verify the audit held, after restarting

1. `claude plugin list` → 3 `✔ enabled`, 8 `✘ disabled`.
2. The agent roster no longer offers `caveman:AGENTS` or `caveman:CLAUDE`.
3. `~/.claude/security/log.txt` stops growing once `security-guidance` is disabled.

A disabled plugin's hooks stay loaded until the process restarts — the security log kept
growing for the remainder of the session in which the plugin was turned off, then stopped.

---

## 6. Disk and MCP notes

- **Duplicate plugin cache.** `~/.claude/plugins/cache/claude-plugins-official/superpowers/`
  can hold both a `6.3.0/` and a `b36e0829c6d0/` directory, 1.6 MB each, identical content,
  with `installed_plugins.json` referencing only one. Disk waste only — the skill listing
  shows each skill once, so it costs no tokens. Not worth deleting a cache entry the plugin
  manager still tracks.
- **No global MCP servers.** An empty `mcpServers` in `~/.claude.json` matters, because MCP
  tool schemas are the single biggest potential context sink.
- **The `github` plugin's MCP server needs a token.** Its `.mcp.json` points at
  `https://api.githubcopilot.com/mcp/` with `Authorization: Bearer
  ${GITHUB_PERSONAL_ACCESS_TOKEN}`. With no `env` block setting that variable, it attempts a
  doomed connection at every startup. If you want this plugin, set the token first:

  ```json
  "env": { "GITHUB_PERSONAL_ACCESS_TOKEN": "ghp_..." }
  ```

  Keep real tokens out of any file you commit.

---

## 7. `ultra` code review is billed, not configured

`/code-review ultra` (alias `/ultrareview`, CLI `claude ultrareview [target]`) is **built
into the CLI binary**, not supplied by the `code-review` plugin — installing or removing
plugins has no effect on it. This is why disabling that plugin (§5) does not touch `ultra`.
It launches a cloud-hosted fleet of agents against the current branch or a PR; a 5-agent
Opus fleet takes ~5–10 min and costs **$5–$25 per run**, charged to extra usage / overage
credits.

So it appears and disappears with **credit state, not settings**. When `~/.claude.json`
shows `cachedExtraUsageDisabledReason: "out_of_credits"` the option is hidden from the slash
menu — nothing is broken and there is no toggle to flip. It returns once extra usage credits
are topped up. Check with:

```
node -e "const c=require(process.env.USERPROFILE+'/.claude.json'); console.log(c.cachedExtraUsageDisabledReason ?? 'credits OK')"
```

It also cannot be launched on your behalf from inside a session — it is user-triggered only.

---

## 8. Not covered here — memory is separate

`MEMORY.md` and `~/.claude/projects/.../memory/*.md` are local files, not a plugin —
installing plugins does **not** copy them. To carry remembered project facts, feedback, and
preferences to a new machine, copy that memory folder separately. It contains whatever the
sessions on that machine chose to remember, so review it before sharing it with anyone.

---

## 9. Settings this repo deliberately does not ship

- `skipDangerousModePermissionPrompt` — suppresses the confirmation before entering
  bypass-permissions mode. Whether to run without that prompt is a per-machine risk
  decision, not a default worth copying.
- A custom `statusLine` command — machine-specific and cosmetic.
- `permissions.allow` entries — each one is a standing grant on your machine. The shipped
  `settings.json` allows only the four `lean-context` converter CLIs, and only if you keep
  that section. Delete it if you do not install them.

---

*The source of truth for what is actually enabled is always `~/.claude/settings.json` plus
`~/.claude/plugins/installed_plugins.json` on the machine in question — re-check before
trusting this file if a lot of time has passed.*
