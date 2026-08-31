#!/usr/bin/env node
// UserPromptSubmit hook: hand the prompt to the shadow arm, then get out of the way.
//
// Whatever this prints on stdout is injected into the session as context, so it prints
// nothing. It also never fails loudly: a benchmarking side-channel must not be able to
// break the session it is measuring, so every path ends in exit 0.
//
// The real work - copying the directory and running the stock config - happens in a
// detached process, because this hook runs before the model sees the prompt and any time
// spent here is latency the user feels.

const fs = require("fs");
const path = require("path");
const { spawn } = require("child_process");
const crypto = require("crypto");

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
const BS = String.fromCharCode(92);
const slash = (v) => String(v).split(BS).join("/");   // cmd and pwsh both take forward slashes

// The shadow arm has to run the model this session is running, or the comparison stops being
// about the configuration: Opus against Sonnet is a 2.5x price difference on its own, which
// would swamp whatever the ruleset does.
//
// Three sources are authoritative, in this order. A pinned config.model wins outright - that is
// what pinning means, and reaching it last (as this did until 2026-08-30) left the pin dead.
// The hook payload is next: Claude Code sends no model with UserPromptSubmit today, so that
// branch is a forward-compatible check rather than a live path. Otherwise it is the newest
// assistant record in the transcript, the only place the running model id is ever written.
//
// settings.json is NOT authoritative and is handed over marked as a guess: a session started
// with --model overrides it, and even when it agrees it holds an alias - "opus", not
// "claude-opus-5" - which writes a second spelling of one model into the ledger and splits the
// dataset the report groups by. That is the first prompt of every session, where no assistant
// record exists yet; the runner waits for one instead of spending the budget on the guess.
// The first prompt of a session is the only one both arms can answer from the same standing
// start: after it, the prompt means whatever the conversation has made it mean, and the shadow
// arm has no conversation. The tell is the same one the model resolution turns on - an assistant
// record exists only once the session has answered something.
function isSessionStart(hook) {
  try {
    const lines = fs.readFileSync(hook.transcript_path, "utf8").split("\n");
    for (const line of lines) {
      if (!line.trim()) continue;
      let rec;
      try { rec = JSON.parse(line); } catch { continue; }
      if (rec.type === "assistant" && rec.message && rec.message.model) return false;
    }
    return true;
  } catch { return false; }   // unreadable transcript: assume not, and let the run be skipped
}

function sessionModel(hook, cfg) {
  if (cfg.model && cfg.model !== "match") return { model: cfg.model, sure: true };
  if (hook.model && typeof hook.model === "string") return { model: hook.model, sure: true };
  if (typeof hook.model === "object" && hook.model && hook.model.id) {
    return { model: hook.model.id, sure: true };
  }
  try {
    const lines = fs.readFileSync(hook.transcript_path, "utf8").split("\n");
    for (let i = lines.length - 1; i >= 0; i--) {
      if (!lines[i].trim()) continue;
      let rec;
      try { rec = JSON.parse(lines[i]); } catch { continue; }
      if (rec.message && rec.message.model) return { model: rec.message.model, sure: true };
    }
  } catch {}
  try {
    const s = JSON.parse(fs.readFileSync(path.join(process.env.USERPROFILE || "", ".claude",
      "settings.json"), "utf8"));
    if (s.model) return { model: s.model, sure: false };
  } catch {}
  return { model: "sonnet", sure: false };
}

function main(input) {
  let hook;
  try { hook = JSON.parse(input); } catch { return; }
  const prompt = hook.prompt;
  if (!prompt || !prompt.trim()) return;

  let cfg;
  try { cfg = JSON.parse(fs.readFileSync(path.join(SHADOW, "config.json"), "utf8")); } catch { return; }
  if (!cfg.enabled) return;

  const id = new Date().toISOString().replace(/[-:T]/g, "").split(".")[0] + "-" +
             crypto.createHash("sha1").update(prompt).digest("hex").slice(0, 6);
  const runDir = path.join(SHADOW, "runs", id);
  fs.mkdirSync(runDir, { recursive: true });
  const promptFile = path.join(runDir, "prompt.txt");
  fs.writeFileSync(promptFile, prompt, "utf8");

  // The Stop hook needs to find this run again to record what Lea did with the same prompt.
  fs.mkdirSync(path.join(SHADOW, ".sessions"), { recursive: true });
  fs.writeFileSync(
    path.join(SHADOW, ".sessions", (hook.session_id || "unknown") + ".json"),
    JSON.stringify({ id, cwd: hook.cwd || process.cwd(), at: new Date().toISOString() }),
    "utf8");

  // Two constraints pull against each other here, and only one launch satisfies both. The
  // runner must outlive this hook, which on Windows needs spawn(detached) - a plain hidden
  // spawn dies with the parent, measured. But detached hands the child its own console, which
  // overrides windowsHide, and that console is the pwsh window that flashed on every prompt.
  // wscript is a GUI-subsystem host: nothing to flash, and it starts pwsh hidden for us.
  const home = process.env.USERPROFILE || "";
  const m = sessionModel(hook, cfg);
  const args = ["//B", "//Nologo",
    slash(path.join(home, ".claude", "hooks", "shadow-hidden-launch.vbs")),
    "pwsh", "-NoProfile", "-File", slash(path.join(SHADOW, "run-shadow.ps1")),
    "-Id", id,
    "-PromptFile", slash(promptFile),
    "-Cwd", slash(hook.cwd || process.cwd()),
    "-Model", m.model];
  // A guess travels with the transcript and a flag, so the runner can wait for the session's
  // first assistant record rather than bill a run under a model name that may not be the one
  // the session is using.
  if (!m.sure) {
    args.push("-ModelGuess");
    if (hook.transcript_path) args.push("-Transcript", slash(hook.transcript_path));
  }
  if (isSessionStart(hook)) args.push("-SessionStart");
  const child = spawn("wscript", args, { detached: true, stdio: "ignore", windowsHide: true });
  child.unref();
}

let data = "";
process.stdin.on("data", (c) => (data += c));
process.stdin.on("end", () => { try { main(data); } catch {} process.exit(0); });
process.stdin.on("error", () => process.exit(0));
setTimeout(() => process.exit(0), 4000).unref();
