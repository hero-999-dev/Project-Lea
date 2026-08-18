#!/usr/bin/env node
// SessionStart hook: prints the personal lean-context skill body, so the converter
// routing rules are in context from the first message instead of waiting for an
// explicit /lean-context.
//
// Node, not PowerShell: SessionStart hooks share a single timeout window, and a
// ~2-3s powershell.exe cold start on Windows would cancel the whole batch -- the same
// outage documented in verification-activate.js.

const fs = require('fs');
const path = require('path');
const os = require('os');

const skill = path.join(os.homedir(), '.claude', 'skills', 'lean-context', 'SKILL.md');

let raw;
try {
  raw = fs.readFileSync(skill, 'utf8');
} catch {
  process.exit(0); // skill removed or renamed -> stay silent, don't break the session
}

const m = raw.match(/^---\r?\n[\s\S]*?\r?\n---\r?\n([\s\S]*)$/);
const body = (m ? m[1] : raw).trim();

process.stdout.write(
  'LEAN-CONTEXT ACTIVE - always-on: route bulky sources through markitdown / trafilatura / duckdb / repomix instead of reading them raw.\n\n'
  + body + '\n'
);
