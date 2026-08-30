# Install the Lea collector: run Lea, and let a shadow arm answer every prompt a second time in
# the background so the two can be compared.
#
# What this touches, and nothing else:
#   ~/.claude/hooks/          three hook files, the hidden launcher, and lea.js
#   ~/.claude/shadow/         the runner, the picker, the report, the ledgers, the run copies
#   ~/.claude/shadow-dir.txt  a one-line pointer so the hooks can find that directory
#   ~/.claude/settings.json   three hook entries, merged - the file is backed up first
#
# Nothing is sent anywhere. Data leaves this machine only when you run export.ps1 yourself.
#
# Usage:  pwsh -NoProfile -File install.ps1 [-Account <label>] [-InstallsOnThisAccount <n>]
#                                           [-SkipLea] [-Force]
#
# Example - four installs, two Claude accounts, two each:
#   pwsh -File install.ps1 -Account A -InstallsOnThisAccount 2

param(
    # A name for the Claude account this install signs in with - "A", "work", anything, as long
    # as the same account gets the same label everywhere. It is a label, never a credential.
    # Installs that share an account share a usage window, and the pooled data is unreadable
    # without knowing which rows were competing for the same one.
    [string]$Account = '',
    # How many installs will run on that account, including this one. The budgets are divided by
    # it, because they are per install and blind to each other: three installs on one account
    # otherwise take three times the intended share of one window.
    [int]$InstallsOnThisAccount = 1,
    # Keep whatever SessionStart configuration is already there instead of installing Lea.
    # The comparison is Lea against a stock config, so without Lea the ledger measures
    # something else - useful only if you know that is what you want.
    [switch]$SkipLea,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$payload = Join-Path $here 'payload'
$claudeDir = Join-Path $HOME '.claude'
$hooksDir = Join-Path $claudeDir 'hooks'
$shadowDir = Join-Path $claudeDir 'shadow'
$settingsPath = Join-Path $claudeDir 'settings.json'

function Say([string]$m, [string]$c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Fail([string]$m) { Write-Host "  x $m" -ForegroundColor Red; exit 1 }

Say ''
Say '  Lea collector' Cyan
Say '  -------------' Cyan

# ---- prerequisites, each named rather than assumed -------------------------------------
$missing = @()
if ($PSVersionTable.PSVersion.Major -lt 7) { $missing += 'PowerShell 7 (pwsh)' }
foreach ($tool in 'node', 'python', 'git') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { $missing += $tool }
}
$claudeExe = @(
    'C:\Users\<name>\.local\bin\claude.exe',
    (Join-Path $HOME '.local\bin\claude.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\claude\claude.exe')
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $claudeExe -and -not (Get-Command claude -ErrorAction SilentlyContinue)) {
    $missing += 'the Claude Code CLI'
}
if ($missing.Count) {
    Say ''
    Fail ("missing: " + ($missing -join ', ') + ". Install those first, then run this again.")
}
Say "  prerequisites ok (pwsh $($PSVersionTable.PSVersion.Major), node, python, git, claude)" Green

# ---- files ------------------------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $hooksDir, $shadowDir | Out-Null
foreach ($f in 'shadow-enqueue.js', 'shadow-collect.js', 'shadow-hidden-launch.vbs') {
    Copy-Item (Join-Path $payload $f) (Join-Path $hooksDir $f) -Force
}
foreach ($f in 'run-shadow.ps1', 'pick.py', 'report.py') {
    Copy-Item (Join-Path $payload $f) (Join-Path $shadowDir $f) -Force
}
Copy-Item (Join-Path $payload 'cfg') $shadowDir -Recurse -Force
Copy-Item (Join-Path $here 'export.ps1') (Join-Path $shadowDir 'export.ps1') -Force

# The config carries your budgets, so an existing one is never overwritten without -Force.
$cfgPath = Join-Path $shadowDir 'config.json'
if ((Test-Path $cfgPath) -and -not $Force) {
    Say '  config.json already exists - kept (use -Force to replace it)' Yellow
}
else {
    Copy-Item (Join-Path $payload 'config.json') $cfgPath -Force
    $conf = Get-Content $cfgPath -Raw | ConvertFrom-Json
    $conf | Add-Member -NotePropertyName account_label -NotePropertyValue $Account -Force
    $conf | Add-Member -NotePropertyName installs_on_this_account `
                       -NotePropertyValue $InstallsOnThisAccount -Force
    if ($InstallsOnThisAccount -gt 1) {
        $n = [double]$InstallsOnThisAccount
        $conf.window_budget_usd = [math]::Round($conf.window_budget_usd / $n, 2)
        $conf.daily_budget_usd = [math]::Round($conf.daily_budget_usd / $n, 2)
        foreach ($m in @($conf.window_budget_by_model.PSObject.Properties.Name)) {
            $conf.window_budget_by_model.$m = [math]::Round($conf.window_budget_by_model.$m / $n, 2)
        }
        # ${...} because PowerShell reads "$name:" as a scope qualifier, not a variable.
        Say "  budgets divided by ${InstallsOnThisAccount}: window `$$($conf.window_budget_usd), day `$$($conf.daily_budget_usd)" Green
    }
    $conf | ConvertTo-Json -Depth 10 | Set-Content $cfgPath -Encoding utf8
}
if (-not $Account) {
    Say '  no -Account label given. Fine for a single install; with more than one, label them' Yellow
    Say '  so the pooled data can tell which rows shared a usage window.' Yellow
}
Set-Content -Path (Join-Path $claudeDir 'shadow-dir.txt') -Value $shadowDir -Encoding utf8 -NoNewline
Say "  files installed into $shadowDir" Green

# ---- Lea itself --------------------------------------------------------------------------
$leaSource = Join-Path (Split-Path $here -Parent) 'config\hooks\lea.js'
$leaTarget = Join-Path $hooksDir 'lea.js'
if (-not $SkipLea) {
    if (-not (Test-Path $leaSource)) { Fail "cannot find $leaSource - run this from inside the repository" }
    Copy-Item $leaSource $leaTarget -Force
    Say '  Lea hook installed' Green
}

# ---- settings.json, merged and backed up --------------------------------------------------
$settings = [ordered]@{}
if (Test-Path $settingsPath) {
    $backup = "$settingsPath.before-lea-collector-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Copy-Item $settingsPath $backup -Force
    Say "  settings.json backed up to $(Split-Path $backup -Leaf)" Green
    $existing = Get-Content $settingsPath -Raw | ConvertFrom-Json
    foreach ($p in $existing.PSObject.Properties) { $settings[$p.Name] = $p.Value }
}

$hooks = [ordered]@{}
if ($settings['hooks']) {
    foreach ($p in $settings['hooks'].PSObject.Properties) { $hooks[$p.Name] = $p.Value }
}
function HookEntry([string]$file, [int]$timeout, [string]$matcher) {
    $cmd = @{ type = 'command'; command = "node `"$(Join-Path $hooksDir $file)`""; timeout = $timeout }
    if ($matcher) { return @(@{ matcher = $matcher; hooks = @($cmd) }) }
    return @(@{ hooks = @($cmd) })
}
if (-not $SkipLea) {
    $hooks['SessionStart'] = HookEntry 'lea.js' 20 'startup|resume|clear|compact'
}
$hooks['UserPromptSubmit'] = HookEntry 'shadow-enqueue.js' 10 ''
$hooks['Stop'] = HookEntry 'shadow-collect.js' 20 ''
$settings['hooks'] = $hooks

$settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding utf8
Say '  settings.json updated (hooks merged, everything else left alone)' Green

Say ''
Say '  Done. Two things to know:' Cyan
Say '   1. Restart Claude Code. The banner should start with LEA ACTIVE.'
Say '   2. Work from a project directory. Prompts sent from your home directory are skipped -'
Say '      except questions answered in the reply, which need no directory at all.'
Say ''
Say "   See what has been collected:  python `"$shadowDir\report.py`""
Say "   Package it to send back:      pwsh -File `"$shadowDir\export.ps1`""
Say "   Stop collecting:              set enabled to false in $cfgPath"
Say ''
