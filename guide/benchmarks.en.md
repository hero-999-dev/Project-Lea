# Benchmark Report — What Each Plugin Actually Costs and Buys

Four measured rounds on one machine, run in a single day for about **$13** of API spend.
The question: is a stacked Claude Code plugin/hook config worth its token cost, and does
the answer depend on the workload?

**It depends on the workload, and the "everything on" default is the wrong one for coding.**

---

## The five configs

Every round compares the same five configurations, isolated with
`--setting-sources project` from a directory with no project settings, plus
`--settings <config-file>`:

| Config | Contents |
|---|---|
| `bare` | no plugins, no custom hooks |
| `hooks` | the two hand-rolled `SessionStart` hooks only (verification + lean-context) |
| `superpowers` | the `superpowers` plugin only |
| `modes` | `caveman` + `ponytail` only |
| `full` | all of the above |

---

## Summary

| Round | n | Cheapest | Best quality | One-line verdict |
|---|---|---|---|---|
| Prose, no tools | 3 | `full`, 36% under `bare` | not measured | caveman's output cut is the whole saving |
| Easy tool bug fix | 3 | `bare` | tie, 15/15 correct | `full` costs +97% for nothing |
| Hard tool bug fix | 5 | `bare` | `superpowers` 3/5, `modes` **0/5** | false-"done" rate is the metric |
| Website build | 3 | `bare` $0.127 / `modes` $0.137 | tie, 14/15 | `modes` fastest and shortest |

**Practical shape:** keep `superpowers` and the verification hook on for coding work, drop
`caveman` and `ponytail` there, and turn them on for prose-heavy sessions. The lever is
`enabledPlugins` plus a restart — saying "stop caveman" mid-session does not recover the
tokens, because the ruleset is already in context.

---

## Round 1 — Prose, no tools

5 configs × 3 samples × 3 turns in one resumed session, Sonnet,
`--permission-mode bypassPermissions`, prompt forbidding files, tools, and clarifying
questions. All 45 calls succeeded, 1 API turn each, no permission denials, **$2.56 total**.

Task: token bucket vs leaky bucket + a Python implementation, then make it thread-safe,
then handle a backward clock jump.

Validity check passed before reading the numbers — every one of the 15 samples produced
code, covered the leaky bucket, used a lock, and reached `time.monotonic()`. Same job
everywhere.

Medians, summed over the 3 turns:

| config | input | output | USD | answer chars |
|---|---:|---:|---:|---:|
| `bare` | 97,580 | 7,940 | 0.175 | 12,772 |
| `hooks` | 101,362 | 9,305 | 0.227 | 12,925 |
| `superpowers` | 103,648 | 9,727 | 0.210 | 13,027 |
| `modes` | 115,231 | 3,139 | 0.143 | 4,661 |
| `full` | 123,904 | 2,436 | **0.112** | 3,990 |

**The headline: `full` reads 27% more input than `bare` and still costs 36% less**, because
output fell 69% and output tokens bill roughly 5× input — and most of that input is cache
reads at a tenth of the input price. **Optimising for prompt size was the wrong target.**

Per component, against `bare`: caveman+ponytail **−18%** cost, and −36% once stacked with
the rest. The hooks alone are **+30%** and superpowers alone **+20%** — both add fixed input
and change output length not at all. Neither pays for itself on this task.

*Caveats:* n=3, one task, no tool use (deliberately suppressed to keep the configs
comparable). This measures prose and code generation only.

---

## Round 2 — Easy agentic bug fix, with real tool use

5 configs × 3 samples, Sonnet, one debugging task: a token bucket whose `_refill`
multiplies elapsed time by `capacity` instead of `refill_rate`, plus a 3-assert
`test_ratelimit.py`. Graded objectively — the suite must exit 0 **and** the test file must
stay byte-identical (SHA256 against the template).

All 15 runs: `is_error=False`, `denials=0`, `test_exit=0`, `test_tampered=no`. Every config
found and fixed the same one-line bug, so the cost numbers compare like for like.

Medians:

| config | input | output | USD | turns | sec | answer chars |
|---|---:|---:|---:|---:|---:|---:|
| `bare` | 156,507 | 667 | **0.119** | 6 | 112 | 172 |
| `hooks` | 163,419 | 681 | 0.128 | 6 | 115 | 261 |
| `modes` | 192,351 | 686 | 0.170 | 6 | 118 | 90 |
| `superpowers` | 257,590 | 1,149 | 0.192 | 9 | 134 | 260 |
| `full` | 267,604 | 796 | **0.234** | 8 | 121 | 109 |

**On tool work every component costs money and none of them saved any.** Against `bare`:
hooks +7%, modes +43%, superpowers +62%, full +97%. The exact opposite of round 1.

The mechanism is output volume. A debugging task emits 600–1,200 output tokens total, so
caveman's compression has almost nothing to compress — it still shortens the final answer
(90 chars vs bare's 172), but that is rounding error against a 190k input. Meanwhile the
fixed ruleset is re-read on all 6–8 turns: input per turn is 26k for `bare` and 33k for
`full`. Superpowers additionally buys 3 extra turns (9 vs 6) from its skill-invocation
mandate.

> **Rule of thumb: caveman/ponytail pay off in proportion to how much prose the model
> writes.** Long-answer chat wins big; multi-turn agentic tool work loses. Claude Code's
> normal usage is the second kind.

*Caveats:* n=3, one easy bug, every config passed — this measures cost at equal quality
only.

---

## Round 3 — Hard agentic bug fix. This is the round that answers the question

The first round that can separate **quality** rather than cost. 5 configs × 5 samples,
25 runs, **$4.65**.

### The task

A `SlidingWindow(limit, window)` rate limiter with an injected clock, whose docstring states
the full contract. It breaks that contract in two places:

- **Bug A** — `allow` appends the timestamp *before* checking, so refused calls occupy a
  slot and a blocked client pushes its own recovery away. The visible `test_limiter.py`
  catches it.
- **Bug B** — `_prune` expires with `events[0] < cutoff` instead of `<=`, so events live one
  instant too long. Documented (`expired once now - t >= window`) but untouched by any
  visible test, which deliberately uses t=11 and t=10.5 rather than the exact boundary.

Grading is a hidden suite copied into the work directory only after the agent exits, public
API only, every assertion traceable to the docstring. The columns that matter are
`visible_exit=0` with `hidden_exit=1` — the agent's own tests green, the fix still wrong —
plus `hidden_pass` (x/8) and a SHA256 tamper check on the visible test file.

Discrimination was proven locally before spending anything: shipped (1,1) · fix-A-only
**(0,1)** · fix-B-only (1,1) · fixed-window rewrite **(0,1)** · correct fix (0,0). A smoke
run confirmed the trap is live on a real agent — `bare` fixed A only, visible exit 0,
hidden 5/8.

### Results

Medians over 5 samples per config:

| config | correct 8/8 | false "done" | input | output | USD | USD per correct fix |
|---|---:|---:|---:|---:|---:|---:|
| `superpowers` | **3/5** | 2 | 223,755 | 2,408 | 0.209 | **0.34** |
| `hooks` | 2/5 | 3 | 165,992 | 1,004 | 0.143 | 0.38 |
| `full` | 2/5 | 3 | 269,471 | 1,164 | 0.244 | 0.65 |
| `bare` | 1/5 | 4 | 160,048 | 803 | 0.134 | 0.66 |
| `modes` | **0/5** | 5 | 193,357 | 748 | 0.173 | **never** |

Validity: 25/25 runs `is_error=False`, `denials=0`, `tampered=no`, `visible_exit=0`. Every
single run left its own test suite green, so **every failure here is a false completion
claim**, not a crash or a refusal.

### The separator is output volume, with no overlap at all

Every wrong fix came in under 1,596 output tokens; every correct one over 1,924 (medians
860 vs 2,690). A perfect split across 25 runs. The runs that wrote more are exactly the runs
that checked the code against the docstring and caught bug B.

That makes caveman/ponytail's own mechanism the thing that costs correctness here: their
entire saving in round 1 came from cutting output 69%, and on this task suppressed output
means the second contract violation is never examined. `modes` went 0/5 while costing 30%
more than `bare` — it pays more and gets less. Stacking it with superpowers (`full`) dragged
superpowers from 3/5 down to 2/5 at the highest cost of any config.

**The verification hook is the cheapest quality lever:** 2/5 versus bare's 1/5 for +7% cost.
**Superpowers is the most effective one:** 3× bare's correctness for +56% cost.

*Caveats:* n=5, one task, one model (Sonnet), and the quality signal rests on a single
hidden defect. The direction is consistent and the output-volume split is clean, but treat
the exact rates as indicative.

---

## Round 4 — Website build from an empty directory

15 runs, **$3.12**. The first round that grades a *built artifact* by driving it.

Task: build a pomodoro timer site that opens straight from `index.html`, with five graded
behaviours stated in the prompt.

Grading is real Chrome over CDP with no dependencies (Node 24 has a global `WebSocket`).
Seven checks — loads, initial 25:00, counts down, pause holds, reset restores, auto-break
(virtual time advanced 1.7M ms past the work session), and no network references. The grader
was validated first against three reference sites: the correct one scores 7/7, a
broken-pause variant fails only `pause_holds`, a no-break variant fails only `auto_break`.

Medians:

| config | 7/7 | input | output | USD | turns | lines | bytes | sec |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `modes` | 3/3 | 75,788 | 1,139 | 0.137 | 2 | **71** | 1,759 | **14** |
| `full` | 3/3 | 167,243 | 1,925 | 0.199 | 4 | 78 | 1,931 | 192 |
| `superpowers` | **2/3** | 109,378 | 2,449 | 0.161 | 4 | 160 | 3,506 | 153 |
| `bare` | 3/3 | 94,500 | 2,302 | **0.127** | 3 | 166 | 3,593 | 148 |
| `hooks` | 3/3 | 203,179 | 3,536 | 0.197 | 6 | 172 | 3,912 | 275 |

14 of 15 sites scored 7/7, so **function did not separate the configs** — this task is easy.
What separated them was volume, speed, and two failure modes:

- **`superpowers` sample 3 produced nothing.** It wrote a design, then ended with "Sound
  good to proceed?" — asking permission in a non-interactive run whose prompt said not to
  ask. Zero files, 1/7. The same failure killed the very first benchmark attempt, so it is
  reproducible and specific to superpowers on generation tasks, not a fluke.
- **`hooks` sample 3 cost $0.86 in one run** — 29 turns, 1.27M input, 17,888 output, against
  a $0.15 median. The verification hook drove it to build its own headless-Chrome harness
  and drive the page over CDP before claiming success. That is the hook working exactly as
  written; the tail risk is that "prove it" has no cost ceiling.

**The volume difference is mostly CSS, not logic.** `modes`/`full` ship ~71–78 lines against
`bare`/`hooks`/`superpowers`' ~160–172. Comparing two samples directly: the JS is 47 vs 71
lines, while the CSS is 6 vs 72. `bare` spent its extra output on a dark theme, a card,
hover/active states, mode colour transitions, tabular numerals and a viewport meta tag. The
caveman/ponytail site is functionally identical and visually plain — and it omits
`<meta name="viewport">`, which is a real mobile defect rather than a matter of taste. The
grader measures behaviour, not appearance, so **"57% less code at identical quality" is only
true for the behaviour it checks.**

---

## Lea v7 vs v8 — the only quality comparison with both arms measured on the same day

`lea` is a sixth configuration that came out of these rounds rather than into them: one
`SessionStart` ruleset of ~180 tokens, no plugins, no dependencies. v8 rewrites a single
paragraph of v7 — the exception that overrides its own word budget — from a permission
(`your analysis is unlimited`) into an obligation (`checking every clause of it against the
implementation is required, not optional`). The size was held deliberately: 220 words → 226.
Nothing else changed.

Both versions were then run on the hard bug fix of round 3, Sonnet, **n=20 per arm**:

| measure | v7 `lea` | v8 `lea-v8` | difference |
|---|---:|---:|---|
| hard-round accuracy — pooled, n=20 | 4/20 | **13/20** | Fisher p=0.010 |
| hard-round accuracy — same day, 29 Aug | 2/14 | **10/15** | Fisher p=0.008 |
| median cost | 0.0954 | 0.0888 | −7% |
| median wall clock | 211 s | 135 s | −36% |
| median input tokens | 165,608 | 132,474 | −20% |
| median output tokens | 1,188 | 1,524 | +28% |
| prose round median — same day, n=5 | 0.0624 | **0.0563** | −10%, p=0.22 |
| prose round output tokens, median | 3,322 | 2,466 | −26% |

**v8 reads less and says more, and is cheaper for it.** It emits 28% more output than v7 and
still has the lower median cost, because its input is 20% smaller. Round 3's volume law holds
inside both arms — correct runs land at 1.8–2.0k output tokens, wrong ones at 0.8–1.2k — but
the volume *distributions* do not separate statistically (Mann-Whitney p=0.25). What moved is
accuracy, not verbosity.

At n=5 the two versions looked tied: 1/5 versus 3/5, p=0.52. The difference only became
visible at the n=20 per arm the plan called for.

**This is the only quality comparison with both arms measured on the same day, and the only
quality finding that reproduced.** That design was forced by what happened to the others:
v7's own 4/5 on the hard round was measured once, on 25 Aug; the byte-identical config scored
1/5 on 26 Aug and 2/14 on 29 Aug, at almost unchanged cost (0.0897 → 0.0882 → 0.1004).
**No quality number resting on a single day was reproduced** — read every one of them, in
every round above, as a measurement of that day rather than of the config.

*Caveats:* v8 was measured on the hard round (n=20) and the prose round (n=5) only. The easy
tool round, the website round and the Opus side are still v7 numbers.

---

## Method notes worth reusing

- **Config isolation:** `--setting-sources project` from a directory with no project
  settings, plus `--settings <config>`. Note `--setting-sources ""` is rejected and silently
  eats the next argument.
- **Force `InvariantCulture` before writing any CSV.** Under a comma-decimal locale (tr-TR)
  the cost field wrote `0,05` and split the column.
- **Launch long rounds detached**, not through an agent tool harness — background runs
  launched that way were killed twice mid-round. `Start-Process pwsh -WindowStyle Hidden
  -RedirectStandardOutput ...` and watch `run.log` for the completion line.
- **`Start-Process -ArgumentList '-File', script, '-Configs', 'modes,full'`** passes the
  configs as one string and every run dies looking for `cfg\modes,full.json`. Use
  `-ArgumentList '-Command', "& 'script' -Configs modes,full"` so PowerShell parses the
  array.
- **Grade with a hidden suite, and hash the visible tests.** Without the tamper check, "all
  tests pass" includes the runs that edited the tests.

### A dead end worth not repeating

The first hard-round design shipped a `_prune` that used `if` instead of `while`, expecting
it to leave expired events behind. It is not a bug — with monotonic timestamps each `allow`
needs at most one free slot, and pruning the single oldest expired event always supplies it,
so behaviour is identical to the `while` version. It passed the hidden suite 7/7. **Any
"drops only one expired entry" bug in a sliding window is unobservable through the public
API.**

### An invalidated benchmark, kept as a warning

An earlier real-task attempt compared configs on the same prompt and produced dramatic
numbers — bare 30,379 median input tokens vs 167,624 for all three plugins. Reading the
actual outputs showed the configs did three *different jobs*, so nothing was comparable:

- superpowers-only asked a clarifying question instead of doing the task (its brainstorming
  mandate turned the request into Q&A). Two of three runs produced ~500 chars and no code.
- modes-only tried to write files, got **permission-denied in `-p` mode**, and retried.
  Those retry loops are what inflated input: every denied tool call is another round trip
  re-reading the ~28k prefix.

So the input explosion measured permission denials and behavioural divergence, not
efficiency. **Always read the outputs before reading the aggregates.** To redo such a
benchmark properly: pick a task needing no file writes and no clarifying questions, pass
`--permission-mode` so tools are not denied, and take more than 3 samples — within-config
spread was already 2×.

---

## What is not measured

- One model (Sonnet) in every round.
- One task per round.
- Small n (3–5) in the four rounds; the v7/v8 comparison is the exception, at n=20 per arm.
- Round 3's quality signal rests on a single hidden defect.
- Cost figures are API pricing at the time of the run, on one account.

The directions are consistent across rounds and the output-volume split in round 3 is clean,
but treat the exact percentages as indicative rather than precise.
