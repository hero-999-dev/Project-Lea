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
//
// Both questions are answered by one bounded pass, and that bound is the whole point. This
// used to be two readFileSync + split of the entire transcript - measured at 1.1 s on a 47 MB
// file, on the critical path of every prompt and growing with the length of the conversation,
// which is what eventually produced "UserPromptSubmit hook timed out after 10s - output
// discarded". A transcript is append-only and the newest assistant record is at its end, so
// read backwards a window at a time and stop at the first one. In a long session that is the
// first window; in a session that has not answered yet the whole file is read, and such a file
// is small by definition.
const WINDOW = 1 << 20;         // 1 MB per read
const MAX_SCAN = 64 << 20;      // and never more than this in total, whatever the file holds

// And a wall clock, because the byte bound alone was not one. The loop stops at the first
// assistant record, so "one window" is the normal case - but a window that happens to hold no
// such record buys another read, and a single tool result can be larger than a window. A session
// whose tail is a run of huge results walks back megabytes, parsing every line, and on a loaded
// machine that reached the 30 s hook budget on 2026-09-04. Raising the budget was the fix last
// time, at 10 s, and it came back; a bound that does not depend on how big the records happen to
// be is the fix that does not.
//
// The process-level setTimeout at the bottom of this file cannot do it: everything here is
// synchronous, so the event loop never gets control and that timer can never fire. A deadline
// inside the loop is the only kind that works.
const SCAN_MS = 400;

function scanTranscript(file) {
  const res = { model: null, answered: false, aborted: false };
  if (!file) return res;
  const deadline = Date.now() + SCAN_MS;
  let fd;
  try { fd = fs.openSync(file, "r"); } catch { return res; }
  try {
    let end = fs.fstatSync(fd).size;
    let scanned = 0;
    while (end > 0 && scanned < MAX_SCAN && !res.model) {
      if (Date.now() > deadline) { res.aborted = true; break; }
      const start = Math.max(0, end - WINDOW);
      const buf = Buffer.alloc(end - start);
      fs.readSync(fd, buf, 0, buf.length, start);
      scanned += buf.length;
      const lines = buf.toString("utf8").split("\n");
      // The window cut this line in half; the window before it owns the whole line. Dropping
      // it is also what keeps a split multi-byte character out of the parse.
      if (start > 0) lines.shift();
      for (let i = lines.length - 1; i >= 0; i--) {
        if (!lines[i].trim()) continue;
        let rec;
        try { rec = JSON.parse(lines[i]); } catch { continue; }
        if (rec.type !== "assistant" || !rec.message || !rec.message.model) continue;
        // "<synthetic>" is Claude Code's own injected assistant record - a usage-limit notice,
        // an API error, an interrupt. It is not an answer and it creates none of the
        // conversational dependency this flag exists to detect, so it must not count as one.
        //
        // It used to. The comment here argued it "still proves the session has produced
        // something", and on 2026-09-02 that cost a measurement: a session opened while the
        // account was over its limit had a synthetic "You've hit your session limit" record
        // written at record 23, before the user had typed anything. The opening prompt arrived
        // 23 s later, read as answered, and was filed as mid-conversation - the one prompt that
        // session could ever have paired. Same failure as the transcript-not-on-disk race fixed
        // the same morning, arriving from the other side.
        if (!/^claude-/i.test(rec.message.model)) continue;
        res.answered = true;
        res.model = rec.message.model;
        break;
      }
      end = start;
    }
  } catch {}
  try { fs.closeSync(fd); } catch {}
  return res;
}

function sessionModel(hook, cfg, scan) {
  if (cfg.model && cfg.model !== "match") return { model: cfg.model, sure: true };
  if (hook.model && typeof hook.model === "string") return { model: hook.model, sure: true };
  if (typeof hook.model === "object" && hook.model && hook.model.id) {
    return { model: hook.model.id, sure: true };
  }
  if (scan.model) return { model: scan.model, sure: true };
  try {
    const s = JSON.parse(fs.readFileSync(path.join(process.env.USERPROFILE || "", ".claude",
      "settings.json"), "utf8"));
    if (s.model) return { model: s.model, sure: false };
  } catch {}
  return { model: "sonnet", sure: false };
}

// Claude Code submits these itself when a usage limit lifts. They arrive through
// UserPromptSubmit exactly like a typed prompt, and they are not one. All three variants in the
// binary share this clause, so one pattern covers the lot:
//   "You can continue now. Continue the task you were working on when the usage limit was
//    reached; do not repeat work that is already complete."
//   "Your claude.ai usage limit has reset. Continue the task you were working on when the limit
//    was reached; ..."
//   "Your claude.ai usage is available again before the usage-limit reset. Continue the task ..."
const AUTO_CONTINUE =
  /Continue the task you were working on when the (?:usage )?limit was reached; do not repeat work that is already complete\./;

function main(input) {
  let hook;
  try { hook = JSON.parse(input); } catch { return; }
  const prompt = hook.prompt;
  if (!prompt || !prompt.trim()) return;

  // Skipped before anything is written, and the pointer is the reason. Letting one of these
  // through opened a new run id and moved .sessions/<id>.json onto it, so the 36 turns and
  // $4.17 Lea spent finishing the task were recorded against a prompt the shadow arm had never
  // seen - while the prompt it HAD copied a 1,651-file tree for could never get a Lea half. The
  // pair split across two ids and neither half was usable. Leaving the pointer alone attributes
  // the continued work to the prompt that started it, which is where it belongs: it is the same
  // task, interrupted by a wall.
  if (AUTO_CONTINUE.test(prompt)) return;

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
  //
  // Its absence is also the only reliable tell that this is the first prompt of the session,
  // and it has to be read before it is written. The transcript cannot answer that question at
  // the one moment it matters: on the first prompt Claude Code has often not written the file
  // yet, the read throws, and "unreadable" used to be resolved as "not a session start" - so
  // the single prompt per session that CAN be paired was the one prompt guaranteed to be
  // thrown away. Measured: of the three session openers that arrived after the rule went live
  // on 2026-08-31, two were skipped as "mid-conversation" for exactly this reason.
  const sessionFile = path.join(SHADOW, ".sessions", (hook.session_id || "unknown") + ".json");
  const firstOfSession = !fs.existsSync(sessionFile);
  fs.mkdirSync(path.join(SHADOW, ".sessions"), { recursive: true });
  fs.writeFileSync(sessionFile,
    JSON.stringify({ id, cwd: hook.cwd || process.cwd(), at: new Date().toISOString() }),
    "utf8");

  // Two constraints pull against each other here, and only one launch satisfies both. The
  // runner must outlive this hook, which on Windows needs spawn(detached) - a plain hidden
  // spawn dies with the parent, measured. But detached hands the child its own console, which
  // overrides windowsHide, and that console is the pwsh window that flashed on every prompt.
  // wscript is a GUI-subsystem host: nothing to flash, and it starts pwsh hidden for us.
  const home = process.env.USERPROFILE || "";
  const scan = scanTranscript(hook.transcript_path);
  const m = sessionModel(hook, cfg, scan);
  const args = ["//B", "//Nologo",
    slash(path.join(home, ".claude", "hooks", "shadow-hidden-launch.vbs")),
    "pwsh", "-NoProfile", "-File", slash(path.join(SHADOW, "run-shadow.ps1")),
    "-Id", id,
    "-PromptFile", slash(promptFile),
    "-Cwd", slash(hook.cwd || process.cwd()),
    "-Model", m.model];
  // An aborted scan resolved no model either, so it is a guess by definition and the runner has
  // to be told where to look. Without this the run would be billed under settings.json's alias -
  // "opus" rather than "claude-opus-5" - which writes a second spelling of one model into the
  // ledger and splits the dataset the report groups by.
  if (scan.aborted) m.sure = false;
  // A guess travels with the transcript and a flag, so the runner can wait for the session's
  // first assistant record rather than bill a run under a model name that may not be the one
  // the session is using.
  if (!m.sure) {
    args.push("-ModelGuess");
    if (hook.transcript_path) args.push("-Transcript", slash(hook.transcript_path));
  }
  // Two signals, both of which must agree, and neither of which can be read off the transcript
  // alone. The pointer file says this hook has not seen the session before; the transcript says
  // the session has not answered anything. A resumed session fails the second even when its id
  // is new, and a session whose transcript is not on disk yet still passes the first.
  //
  // `aborted` is a third answer and it is not "no". The scan gave up on its deadline without
  // reaching a verdict, so the session may well have answered already; claiming a session start
  // on a pointer file alone would file a mid-conversation prompt as pairable, and a false pair
  // is worse than a missed one - it enters the medians. Missing one costs a measurement that was
  // never guaranteed anyway.
  if (firstOfSession && !scan.answered && !scan.aborted) args.push("-SessionStart");
  const child = spawn("wscript", args, { detached: true, stdio: "ignore", windowsHide: true });
  child.unref();
}

let data = "";
process.stdin.on("data", (c) => (data += c));
process.stdin.on("end", () => { try { main(data); } catch {} process.exit(0); });
process.stdin.on("error", () => process.exit(0));
setTimeout(() => process.exit(0), 4000).unref();
