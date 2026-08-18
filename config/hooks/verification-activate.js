#!/usr/bin/env node
// SessionStart hook: injects the always-on verification-before-completion rule.
//
// Node, not PowerShell: powershell.exe cold start is ~2-3s on Windows and can spike past
// the 5s SessionStart budget, which cancels the WHOLE hook batch -- every other plugin
// activation dies with it. Node starts in ~200ms.
//
// The text is inlined rather than read out of the superpowers SKILL.md. That file is
// ~3.6 KB of tables and rationalization lists; the enforceable core is the Iron Law and
// the gate, ~0.7 KB. Inlining also drops the dependency on superpowers being installed
// and on guessing which cache dir (version name vs commit sha) is current.
//
// The full skill is still reachable on demand: /superpowers:verification-before-completion

process.stdout.write(`VERIFICATION-BEFORE-COMPLETION ACTIVE - always-on: evidence before every completion claim, no exceptions.

# The Iron Law

NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE.
If you have not run the verification command in this message, you cannot claim it passes.

# The gate

Before any claim of status, completion, or satisfaction:
1. Name the command that proves the claim.
2. Run it fresh, in full.
3. Read the whole output. Check the exit code. Count the failures.
4. Claim only what that output supports, and state the evidence alongside the claim.

Skipping a step is lying, not verifying.

# Red flags - stop and verify

"should work" / "probably" / "seems to"; any "Done!" or "Perfect!" before evidence;
trusting a subagent's success report instead of checking the diff; a passing linter
standing in for a build; one green run standing in for a red-green regression check;
"just this once", "I'm confident", "partial check is enough".

This covers paraphrases and implications of success, not only these exact phrases.
`);
