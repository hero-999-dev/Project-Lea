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
// would swamp whatever the ruleset does. settings.json is not the answer either - it can say
// "sonnet" while the session runs Opus - so the transcript is the source of truth, and the
// static values are only fallbacks for the first prompt of a session.
function sessionModel(hook, cfg) {
  if (hook.model && typeof hook.model === "string") return hook.model;
  if (typeof hook.model === "object" && hook.model && hook.model.id) return hook.model.id;
  try {
    const lines = fs.readFileSync(hook.transcript_path, "utf8").split("\n");
    for (let i = lines.length - 1; i >= 0; i--) {
      if (!lines[i].trim()) continue;
      let rec;
      try { rec = JSON.parse(lines[i]); } catch { continue; }
      if (rec.message && rec.message.model) return rec.message.model;
    }
  } catch {}
  try {
    const s = JSON.parse(fs.readFileSync(path.join(process.env.USERPROFILE || "", ".claude",
      "settings.json"), "utf8"));
    if (s.model) return s.model;
  } catch {}
  return cfg.model && cfg.model !== "match" ? cfg.model : "sonnet";
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
  const child = spawn("wscript", ["//B", "//Nologo",
    slash(path.join(home, ".claude", "hooks", "shadow-hidden-launch.vbs")),
    "pwsh", "-NoProfile", "-File", slash(path.join(SHADOW, "run-shadow.ps1")),
    "-Id", id,
    "-PromptFile", slash(promptFile),
    "-Cwd", slash(hook.cwd || process.cwd()),
    "-Model", sessionModel(hook, cfg)],
    { detached: true, stdio: "ignore", windowsHide: true });
  child.unref();
}

let data = "";
process.stdin.on("data", (c) => (data += c));
process.stdin.on("end", () => { try { main(data); } catch {} process.exit(0); });
process.stdin.on("error", () => process.exit(0));
setTimeout(() => process.exit(0), 4000).unref();
