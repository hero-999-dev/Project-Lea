# Project Lea

A measurement lab for Claude Code configurations, and the configuration it produced.

The lab is a resumable benchmark harness: **286 graded agent runs** over five task types,
seven configurations and two models, marked by hidden test suites the agent never sees and by
a real browser driven over CDP — plus a round on a live production site instead of a toy task.
It survives usage limits, resumes mid-matrix, and keeps every failed stream instead of
overwriting it.

**Lea** is what came out of the data: one 226-word `SessionStart` hook, no plugins and no
dependencies, that matched or beat 6,000-token plugin stacks at 13–53% lower cost. Rewriting a
single paragraph of it — the exception clause, from permission to obligation — took the hard
round from 4/20 correct to 13/20, with both arms measured the same day.

**📖 The full report is `docs/index.html`** — clone or download the repository and open that
file in a browser. It is a single self-contained page: no server, no build step, no network
calls. (It is not published as a website; the repository is private.)
**📦 Full report as a downloadable archive →** [Releases](../../releases/latest)

Everything here is bilingual: **English** and **Türkçe**.

---

## The short version

Eleven enabled plugins went to three, after measuring what each one costs on every session
before you type anything. Then four benchmark rounds (~$13 of API spend) checked whether the
survivors were worth their token cost. The answer turned out to depend entirely on the
workload:

| Workload | Verdict |
|---|---|
| Long-form prose and explanation | `caveman` + `ponytail` are **36% cheaper** than a bare config — output falls 69%, and output bills ~5× input |
| Easy agentic tool work | Nothing pays for itself. A bare config wins; everything on costs **+97%** for identical results |
| Hard agentic work, where the fix can be wrong | `superpowers` gets **3/5** correct vs bare's 1/5. `caveman`+`ponytail` get **0/5** — their output compression is exactly what stops the model from re-checking its work |

**The practical shape:** `superpowers` + a verification hook for coding, `caveman` +
`ponytail` for prose-heavy sessions, and no single config that is right for both.

Two non-obvious findings that will save you time regardless of which plugins you pick:

- **One slow `SessionStart` hook cancels every other one.** They share a single timeout
  window. A PowerShell hook that took 5738 ms against a 5000 ms budget silently took three
  plugins down with it, and the session looked like nothing was ever installed.
- **Trimming the skill list saves no tokens.** The listing is capped by
  `skillListingBudgetFraction`; remove a skill and the survivors just get longer
  descriptions. Trimming buys triggering accuracy, not tokens.

---

## Contents

| Path | What it is |
|---|---|
| [`INSTALL.md`](INSTALL.md) · [`INSTALL.tr.md`](INSTALL.tr.md) | Step-by-step install. Written so you can hand it to your own Claude Code session and let it do the work |
| [`guide/setup-guide.en.md`](guide/setup-guide.en.md) · [`.tr.md`](guide/setup-guide.tr.md) | The full reference: what is installed, what was disabled and why, and every gotcha that cost real debugging time |
| [`guide/benchmarks.en.md`](guide/benchmarks.en.md) · [`.tr.md`](guide/benchmarks.tr.md) | The four measured rounds, with method notes and the invalidated attempt kept as a warning |
| [`config/settings.json`](config/settings.json) | `~/.claude/settings.json` template — merge it, don't overwrite |
| [`config/hooks/`](config/hooks/) | Two hand-rolled always-on `SessionStart` hooks (Node, cross-platform) |
| [`config/skills/lean-context/`](config/skills/lean-context/) | A personal skill that routes bulky files through local converters instead of reading them raw |
| [`docs/index.html`](docs/index.html) | The website version of the report — one self-contained file, opens offline |

---

## Quick start

```bash
git clone https://github.com/hero-999-dev/Project-Lea.git
cd Project-Lea
```

Then either read [`INSTALL.md`](INSTALL.md) yourself, or start a Claude Code session in the
clone and say:

> Read INSTALL.md and set this up for me.

Step 0 of that file is a decision, not a command — it asks which parts you actually want,
because the benchmark says installing all of them is the wrong default for coding work.

---

## Caveats, stated up front

The benchmarks are n=3–5, one task per round, one model (Sonnet), on one machine. The
directions are consistent and the round-3 output-volume split is clean, but treat the exact
percentages as indicative rather than precise. Cost figures are API pricing at the time of
the runs.

Nothing here is affiliated with Anthropic. `superpowers` is an official marketplace plugin;
[`ponytail`](https://github.com/DietrichGebert/ponytail) and
[`caveman`](https://github.com/JuliusBrussee/caveman) are third-party plugins by their
respective authors — this repo only measures and configures them.

---

## What this repo deliberately does not contain

No machine-specific paths, no account identifiers, no tokens or credentials, no session
transcripts, no memory files, and no permission-weakening settings. The shipped
`settings.json` is a template with a placeholder where the home directory goes. If you fork
this and add your own config, check it the same way before pushing.
