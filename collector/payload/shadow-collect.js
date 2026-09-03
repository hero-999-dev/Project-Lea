#!/usr/bin/env node
// Stop hook: record what Lea's own turn cost, and what it changed, against the same base
// the shadow arm started from.
//
// Cost is priced from the transcript rather than read off a summary field, for the reason the
// benchmark learned the hard way: the summary can describe one leg of a restarted session.
// Per-token prices are the ones fitted from 205 clean benchmark rows (mean error 0.17%).
//
// Silent and exit 0 on every path - this must never be able to break a session.

const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

// Where the shadow directory lives. A collector install puts it at ~/.claude/shadow; this
// machine keeps it inside the benchmark project, so a one-line pointer file wins when present.
// Neither hook may hardcode a path: the same two files ship to other machines and other users.
function shadowDir() {
  const home = process.env.USERPROFILE || process.env.HOME || "";
  try {
    const p = fs.readFileSync(path.join(home, ".claude", "shadow-dir.txt"), "utf8").trim();
    if (p && fs.existsSync(p)) return p;
  } catch {}
  return path.join(home, ".claude", "shadow");
}

const SHADOW = shadowDir();
const PRICE = {                       // $ per token: cache-write, cache-read, output
  opus:   { cw: 9.99e-6, cr: 0.501e-6, out: 25.02e-6 },
  sonnet: { cw: 6.01e-6, cr: 0.300e-6, out: 15.03e-6 },
};

// Two Windows users on one machine point at one shadow directory, so two processes can reach
// this line at once. A torn row is the one thing a ledger cannot survive, so appends go through
// a lock file both writers understand - the PowerShell runner takes the same one.
const LOCK = path.join(SHADOW, ".ledger.lock");

function sleepSync(ms) {
  try { Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms); } catch {}
}

function appendLocked(file, line) {
  const deadline = Date.now() + 3000;
  let held = false;
  while (Date.now() < deadline) {
    try { fs.closeSync(fs.openSync(LOCK, "wx")); held = true; break; } catch {}
    // A lock older than the longest write anyone here does is a crashed writer, not a busy one.
    try { if (Date.now() - fs.statSync(LOCK).mtimeMs > 10000) fs.unlinkSync(LOCK); } catch {}
    sleepSync(25);
  }
  try { fs.appendFileSync(file, line, "utf8"); }
  finally { if (held) { try { fs.unlinkSync(LOCK); } catch {} } }
}

// Which ruleset actually produced this row. A second install that still has its plugins on is
// not running Lea, and a row from it must not be filed under Lea's name - that is the one
// failure a benchmark cannot survive, because the row still looks like evidence.
function liveConfig() {
  try {
    const home = process.env.USERPROFILE || process.env.HOME || "";
    const s = JSON.parse(fs.readFileSync(path.join(home, ".claude", "settings.json"), "utf8"));
    const plugins = Object.values(s.enabledPlugins || {}).filter(Boolean).length;
    const starts = JSON.stringify((s.hooks && s.hooks.SessionStart) || []);
    const hasLea = /lea\.js/i.test(starts);
    if (hasLea && plugins === 0) return "lea";
    if (hasLea) return "lea+" + plugins + "plugins";
    return plugins ? "other+" + plugins + "plugins" : "other";
  } catch { return "unknown"; }
}

function priceOf(model) {
  const m = (model || "").toLowerCase();
  if (m.includes("opus")) return PRICE.opus;
  if (m.includes("haiku")) return PRICE.sonnet;   // no fitted haiku vector; sonnet is the closest
  return PRICE.sonnet;
}

function sessionCost(transcriptPath) {
  // Sum every assistant message in the transcript. Cache reads are billed per call, so they
  // are summed too rather than counted once.
  //
  // The input counts are summed for the same reason the cost is: what this turn had to read is
  // the whole difference between the two arms. Lea answers inside a session and pays to re-read
  // it on every turn; the shadow arm answers the same prompt from an empty context. Recording
  // both sides is what lets the report say which numbers are comparable and which are not.
  let total = 0, out = 0, turns = 0, model = "", cr = 0, inp = 0;
  let text;
  try { text = fs.readFileSync(transcriptPath, "utf8"); } catch { return null; }
  for (const line of text.split("\n")) {
    if (!line.trim()) continue;
    let rec;
    try { rec = JSON.parse(line); } catch { continue; }
    const msg = rec.message;
    if (!msg || !msg.usage) continue;
    const u = msg.usage, p = priceOf(msg.model);
    model = msg.model || model;
    total += (u.cache_creation_input_tokens || 0) * p.cw +
             (u.cache_read_input_tokens || 0) * p.cr +
             (u.output_tokens || 0) * p.out +
             (u.input_tokens || 0) * p.cw / 1.25;
    out += u.output_tokens || 0;
    cr += u.cache_read_input_tokens || 0;
    inp += (u.input_tokens || 0) + (u.cache_creation_input_tokens || 0);
    turns += 1;
  }
  return { total, out, turns, model, cr, inp };
}

// `user` and `host` are not bookkeeping: with two installs writing one ledger, a row that does
// not say who wrote it cannot be told apart from one written under a different account, budget
// or model, and a difference between installs would read as a difference between configs.
const LEA_HEADER = "id,when,model,cost_usd,turns,output_tokens,cwd," +
  "input_tokens,cache_read_tokens,turns_before,user,host,lea_config\n";

function csvRow(values) {
  return values.map((v) => {
    const s = v === undefined || v === null ? "" : String(v);
    return /[",\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
  }).join(",");
}

function main(input) {
  let hook;
  try { hook = JSON.parse(input); } catch { return; }
  const sid = hook.session_id || "unknown";

  const pointerPath = path.join(SHADOW, ".sessions", sid + ".json");
  let pointer;
  try { pointer = JSON.parse(fs.readFileSync(pointerPath, "utf8")); } catch { return; }
  const runDir = path.join(SHADOW, "runs", pointer.id);
  if (!fs.existsSync(runDir)) return;

  // There used to be a "one row per prompt" gate here. It had to go once the enqueue hook
  // stopped letting Claude Code's own auto-continue prompts move the pointer: the work that
  // finishes a task after a usage limit lifts now belongs to the prompt that started it, and it
  // arrives at a LATER Stop. Gating on the first row would have thrown that work away entirely -
  // in the case that prompted this, 36 turns and $4.17 of it.
  //
  // Two rows for one id do not double-count, because each Stop records only what has happened
  // since the previous one; report.py and savings.py sum them. What is guarded instead is the
  // empty case below: a Stop that fires with no new turn writes nothing.
  const now = sessionCost(hook.transcript_path);
  if (!now) return;

  // The session total minus what it was at the end of the previous turn is this turn's cost.
  const statePath = path.join(SHADOW, ".sessions", sid + ".cost.json");
  let before = { total: 0, out: 0, turns: 0, cr: 0, inp: 0 };
  try { before = JSON.parse(fs.readFileSync(statePath, "utf8")); } catch {}
  const cost = now.total - before.total;
  const outTok = now.out - before.out;
  const turns = now.turns - before.turns;
  const crTok = now.cr - (before.cr || 0);
  const inTok = now.inp - (before.inp || 0);
  const turnsBefore = before.turns || 0;      // how deep into the session this prompt arrived
  fs.writeFileSync(statePath, JSON.stringify(now), "utf8");

  // A Stop can fire without a turn having happened - an interrupt, a permission prompt answered
  // and abandoned. The state above is still updated, so nothing drifts; only the empty row is
  // skipped, because a zero row in the ledger is noise a later reader has to explain away.
  if (turns <= 0 && cost <= 0) return;

  // Lea's diff, taken against the copy the shadow arm started from: same ancestor, so the
  // two patches are directly comparable.
  const base = path.join(runDir, "base");
  if (fs.existsSync(base)) {
    const r = leaPatch(base, pointer.cwd);
    if (r.failed) {
      // Recorded, not swallowed. This used to be `if (r.stdout) write(...)`, which made a diff
      // that never ran look exactly like a diff that found nothing - and since prune() waits
      // for both patches, every failure also pinned a full copy of the tree on disk forever.
      fs.writeFileSync(path.join(runDir, "lea.stat.error"), r.failed, "utf8");
    } else {
      // Written even when empty. "Lea changed no files" is a result, and the only honest way to
      // say it is a patch with nothing in it.
      fs.writeFileSync(path.join(runDir, "lea.stat"), r.patch, "utf8");
    }
  }

  const csv = path.join(SHADOW, "lea.csv");
  if (!fs.existsSync(csv)) {
    fs.writeFileSync(csv, LEA_HEADER, "utf8");
  }
  appendLocked(csv, csvRow([pointer.id, new Date().toISOString().slice(0, 19).replace("T", " "),
    now.model, cost.toFixed(6), turns, outTok, pointer.cwd,
    inTok, crTok, turnsBefore,
    process.env.USERNAME || process.env.USER || "",
    process.env.COMPUTERNAME || "", liveConfig()]) + "\n");
  fs.writeFileSync(path.join(runDir, "lea.recorded"), "", "utf8");
  prune();
}

// Each run holds two copies of the project, so a 50 MB project costs 100 MB per prompt. Only
// the newest few keep their trees; older runs are cut down to the prompt, the result and the
// two patches, which is all a later comparison reads. Never touches a run that is still
// missing a patch - the shadow arm may still be working in it.
// Lea's side of the comparison, taken one top-level entry at a time.
//
// Not `git diff --no-index base cwd` any more, which is what this was. That walks both sides
// exhaustively, and cwd contains shadow/runs/ - every earlier run's copy of this same tree. It
// reached 2.2 GB, and a path inside one of those copies grew long enough that git gave up with
// "error: Could not access ...", wrote nothing to stdout, and exited 1. The caller only checked
// stdout, so the failure was invisible; no lea.stat meant prune() could never reclaim the tree,
// which made the next diff slower and likelier to fail. Every comparable pair collected so far
// lost its Lea-side diff to this, which is the one signal that says whether the two arms did the
// same amount of work.
//
// base holds exactly what config.copy.exclude_dirs allowed through - no shadow/, no runs/, no
// .git - so diffing per entry of base compares that same set and never descends into the rest.
// Long paths are enabled because the copies nest deeply enough to pass MAX_PATH on their own.
//
// It records --numstat, not the patch text. Once the walk was fixed the full binary diff came
// out at 68 MB for a single prompt and still overflowed a 64 MB buffer on one entry, because
// Lea's side spans a whole session in a live tree rather than one agent's edits in a scratch
// copy. Three columns per file - added, removed, path - answer what the pair is for: did the two
// arms touch the same files, and to the same extent, or did the cheaper arm simply do less. That
// fits in a few KB, cannot overflow, and carries no source code off the machine when exported.
function leaPatch(base, cwd) {
  const parts = [];
  let failed = null;
  let names;
  try { names = fs.readdirSync(base); } catch (e) { return { patch: "", failed: String(e) }; }
  for (const name of names) {
    const r = spawnSync("git", ["-c", "core.longpaths=true", "diff", "--no-index", "--numstat",
      "--", path.join(base, name), path.join(cwd, name)],
      { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
    if (r.stdout) parts.push(r.stdout);
    // git answers 0 when the two are identical and 1 when they differ. Both are success here.
    // Anything else - a spawn failure, an unreadable path, a patch past maxBuffer - is not.
    if (r.error || (r.status !== 0 && r.status !== 1)) {
      const why = (r.error && r.error.message) || (r.stderr || "").trim() ||
                  ("git exited " + r.status);
      failed = (failed ? failed + "\n" : "") + name + ": " + why.slice(0, 400);
    }
  }
  return { patch: parts.join(""), failed };
}


function prune() {
  let keep = 5;
  try {
    keep = JSON.parse(fs.readFileSync(path.join(SHADOW, "config.json"), "utf8")).keep_trees_last_n;
  } catch {}
  if (!Number.isFinite(keep) || keep < 0) return;
  const runs = path.join(SHADOW, "runs");
  let ids;
  try { ids = fs.readdirSync(runs).sort(); } catch { return; }
  for (const id of ids.slice(0, Math.max(0, ids.length - keep))) {
    const dir = path.join(runs, id);
    // A queued run is not finished, whatever patches it has. Its base/ is the ancestor the
    // retry has to start from, and deleting that would leave a deferred run that can never
    // produce a comparable answer - it would run against a tree Lea had already changed.
    if (fs.existsSync(path.join(dir, "deferred.json"))) continue;
    // A run whose Lea-side diff failed is finished too, in the only sense that matters here:
    // cwd has moved on, so the diff can never be retaken, and the tree is dead weight from that
    // moment. Treating it as unfinished is what let runs/ grow to 2.2 GB.
    // lea.patch is the pre-2026-09-03 name, when this was a full diff. Runs from before the
    // rename still hold one and are just as finished as the ones that hold a lea.stat.
    const leaDone = ["lea.stat", "lea.stat.error", "lea.patch"]
      .some((f) => fs.existsSync(path.join(dir, f)));
    const done = leaDone && fs.existsSync(path.join(dir, "shadow.patch"));
    if (!done) continue;
    for (const tree of ["base", "work"]) {
      try { fs.rmSync(path.join(dir, tree), { recursive: true, force: true }); } catch {}
    }
  }
}

let data = "";
process.stdin.on("data", (c) => (data += c));
process.stdin.on("end", () => { try { main(data); } catch {} process.exit(0); });
process.stdin.on("error", () => process.exit(0));
setTimeout(() => process.exit(0), 8000).unref();
