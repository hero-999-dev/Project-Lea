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

function priceOf(model) {
  const m = (model || "").toLowerCase();
  if (m.includes("opus")) return PRICE.opus;
  if (m.includes("haiku")) return PRICE.sonnet;   // no fitted haiku vector; sonnet is the closest
  return PRICE.sonnet;
}

function sessionCost(transcriptPath) {
  // Sum every assistant message in the transcript. Cache reads are billed per call, so they
  // are summed too rather than counted once.
  let total = 0, out = 0, turns = 0, model = "";
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
    turns += 1;
  }
  return { total, out, turns, model };
}

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
  if (fs.existsSync(path.join(runDir, "lea.recorded"))) return;   // one row per prompt

  const now = sessionCost(hook.transcript_path);
  if (!now) return;

  // The session total minus what it was at the end of the previous turn is this turn's cost.
  const statePath = path.join(SHADOW, ".sessions", sid + ".cost.json");
  let before = { total: 0, out: 0, turns: 0 };
  try { before = JSON.parse(fs.readFileSync(statePath, "utf8")); } catch {}
  const cost = now.total - before.total;
  const outTok = now.out - before.out;
  const turns = now.turns - before.turns;
  fs.writeFileSync(statePath, JSON.stringify(now), "utf8");

  // Lea's diff, taken against the copy the shadow arm started from: same ancestor, so the
  // two patches are directly comparable.
  const base = path.join(runDir, "base");
  if (fs.existsSync(base)) {
    const r = spawnSync("git", ["diff", "--no-index", "--binary", "--", base, pointer.cwd],
      { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
    if (r.stdout) fs.writeFileSync(path.join(runDir, "lea.patch"), r.stdout, "utf8");
  }

  const csv = path.join(SHADOW, "lea.csv");
  if (!fs.existsSync(csv)) {
    fs.writeFileSync(csv, "id,when,model,cost_usd,turns,output_tokens,cwd\n", "utf8");
  }
  fs.appendFileSync(csv, csvRow([pointer.id, new Date().toISOString().slice(0, 19).replace("T", " "),
    now.model, cost.toFixed(6), turns, outTok, pointer.cwd]) + "\n", "utf8");
  fs.writeFileSync(path.join(runDir, "lea.recorded"), "", "utf8");
  prune();
}

// Each run holds two copies of the project, so a 50 MB project costs 100 MB per prompt. Only
// the newest few keep their trees; older runs are cut down to the prompt, the result and the
// two patches, which is all a later comparison reads. Never touches a run that is still
// missing a patch - the shadow arm may still be working in it.
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
    const done = fs.existsSync(path.join(dir, "lea.patch")) &&
                 fs.existsSync(path.join(dir, "shadow.patch"));
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
