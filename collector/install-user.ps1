# Install Lea and the shadow arm into a SECOND Windows profile on this machine, pointing it at
# the ledger the first one already writes.
#
# Why this exists as its own script. `install.ps1` sets up one machine as one contributor: it
# puts the shadow directory under that profile's own ~/.claude and refuses to repoint an
# existing one. That is right for a fresh machine and wrong for the case here - two Windows
# users, one person, one project - where the second install must join the first one's ledger
# rather than start a parallel one nobody reads. The rows carry `user` and `host`, so a joined
# ledger is still separable afterwards; without those columns it would not be.
#
# What it touches in <TargetHome>, and nothing else:
#   .claude\hooks\            lea.js, shadow-enqueue.js, shadow-collect.js, the hidden launcher
#   .claude\shadow-dir.txt    a one-line pointer at the SHARED shadow directory
#   .claude\settings.json     three hook entries merged, enabledPlugins switched off, and
#                             autoContinueAtUsageLimit turned on so a session that hits the
#                             5-hour usage limit waits for the reset and carries on instead of
#                             ending. -NoAutoContinue leaves that toggle alone.
#   .claude\statusline.ps1    optional, only with -Statusline
#
# Every file it overwrites is backed up next to itself first. Nothing is sent anywhere.
#
# Usage:
#   pwsh -NoProfile -File install-user.ps1 -TargetHome C:\Users\<name> -SharedShadow <dir> [-WhatIf]
#
# Run it from an account that can write into <TargetHome> - on Windows that normally means an
# administrator, or the target user themselves.

param(
    # The profile to install into, e.g. C:\Users\<name>. Not the current one by default: this
    # script exists to touch someone else's home, so naming it is deliberate.
    [Parameter(Mandatory = $true)][string]$TargetHome,

    # The shadow directory both installs write to. Must already exist - this script joins a
    # ledger, it does not create one.
    [Parameter(Mandatory = $true)][string]$SharedShadow,

    # Where the hook files come from. Defaults to this repo, which is the source of record.
    [string]$Source = '',

    # Also install a statusline (this file is not part of the published repo; pass a path).
    [string]$Statusline = '',

    # Leave enabledPlugins alone. Use it only if you know what you are doing: a session with
    # plugins on is not Lea, and its rows will be filed under lea_config = "lea+Nplugins".
    [switch]$KeepPlugins,

    # Leave autoContinueAtUsageLimit as you had it. On by default because a session that ends at
    # the 5-hour limit loses that prompt's measurement: the shadow arm's row is already written
    # and Lea's turn never is, so the pair is half-recorded rather than merely late.
    [switch]$NoAutoContinue,

    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
function Say([string]$m, [string]$c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Fail([string]$m) { Write-Host "  x $m" -ForegroundColor Red; exit 1 }
function Did([string]$m) { Write-Host "  + $m" -ForegroundColor Green }
function Skip([string]$m) { Write-Host "  - $m" -ForegroundColor DarkGray }

$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if (-not $Source) { $Source = Split-Path -Parent $PSScriptRoot }   # the repo root

# ---- checks, each named rather than assumed ------------------------------------------------
if (-not (Test-Path -LiteralPath $TargetHome)) { Fail "no such profile: $TargetHome" }
if (-not (Test-Path -LiteralPath $SharedShadow)) {
    Fail "shared shadow directory does not exist: $SharedShadow
      This script joins an existing ledger. Create it with install.ps1 on the first profile."
}
foreach ($n in @('shadow.csv', 'lea.csv', 'config.json')) {
    if (-not (Test-Path -LiteralPath (Join-Path $SharedShadow $n))) {
        Say "  ! $SharedShadow has no $n yet - it will be created on the first run" 'Yellow'
    }
}

# The hook files. lea.js is the repo's own copy; the shadow pair ships in collector\payload.
$Files = @(
    @{ From = (Join-Path $Source 'config\hooks\lea.js');                       To = 'lea.js' }
    @{ From = (Join-Path $PSScriptRoot 'payload\shadow-enqueue.js');           To = 'shadow-enqueue.js' }
    @{ From = (Join-Path $PSScriptRoot 'payload\shadow-collect.js');           To = 'shadow-collect.js' }
    @{ From = (Join-Path $PSScriptRoot 'payload\shadow-hidden-launch.vbs');    To = 'shadow-hidden-launch.vbs' }
)
foreach ($f in $Files) {
    if (-not (Test-Path -LiteralPath $f.From)) { Fail "missing source file: $($f.From)" }
}

$Dot = Join-Path $TargetHome '.claude'
$Hooks = Join-Path $Dot 'hooks'
$Settings = Join-Path $Dot 'settings.json'

Say ""
Say "Lea + shadow -> $TargetHome" 'Cyan'
Say "  ledger       $SharedShadow"
Say "  sources      $Source"
if ($WhatIf) { Say "  (-WhatIf: nothing will be written)" 'Yellow' }
Say ""

function Backup([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $b = "$Path.pre-lea-$Stamp"
    if (-not $WhatIf) { Copy-Item -LiteralPath $Path -Destination $b -Force }
    return $b
}

# ---- files -----------------------------------------------------------------------------------
if (-not $WhatIf) { New-Item -ItemType Directory -Force -Path $Hooks | Out-Null }
foreach ($f in $Files) {
    $dest = Join-Path $Hooks $f.To
    $same = (Test-Path -LiteralPath $dest) -and
            ((Get-FileHash -LiteralPath $dest).Hash -eq (Get-FileHash -LiteralPath $f.From).Hash)
    if ($same) { Skip "hooks\$($f.To) already current"; continue }
    $b = Backup $dest
    if (-not $WhatIf) { Copy-Item -LiteralPath $f.From -Destination $dest -Force }
    Did "hooks\$($f.To)$(if ($b) { ' (old copy kept)' })"
}
if ($Statusline) {
    if (-not (Test-Path -LiteralPath $Statusline)) { Fail "no such statusline: $Statusline" }
    $dest = Join-Path $Dot 'statusline.ps1'
    $b = Backup $dest
    if (-not $WhatIf) { Copy-Item -LiteralPath $Statusline -Destination $dest -Force }
    Did "statusline.ps1$(if ($b) { ' (old copy kept)' })"
}

# ---- the pointer -------------------------------------------------------------------------------
# Both installs resolve the shadow directory through this file, which is what makes one ledger
# out of two profiles. Repointing an existing one would orphan whatever it names, so say so.
$Ptr = Join-Path $Dot 'shadow-dir.txt'
$existing = if (Test-Path -LiteralPath $Ptr) { (Get-Content -LiteralPath $Ptr -Raw).Trim() } else { '' }
if ($existing -and $existing -ne $SharedShadow) {
    Say "  ! shadow-dir.txt already points at $existing" 'Yellow'
    Say "    Repointing it leaves those rows with nothing writing to them. Move or merge them first." 'Yellow'
    Fail "refusing to repoint an existing ledger"
}
if ($existing -eq $SharedShadow) { Skip 'shadow-dir.txt already correct' }
else {
    if (-not $WhatIf) { [IO.File]::WriteAllText($Ptr, $SharedShadow) }
    Did 'shadow-dir.txt'
}

# ---- settings.json ------------------------------------------------------------------------------
# PowerShell unwraps a one-element array on return, which silently turns a hooks LIST into a
# hooks OBJECT and drops fields. `return ,@(...)` is what keeps it a list.
function HookEntry([string]$Command, [int]$Timeout, [string]$Matcher, [string]$Message) {
    $h = [ordered]@{ type = 'command'; command = $Command; timeout = $Timeout }
    if ($Message) { $h.statusMessage = $Message }
    $entry = [ordered]@{}
    if ($Matcher) { $entry.matcher = $Matcher }
    $entry.hooks = @($h)
    return , @($entry)
}

$node = 'node "{0}"'
$s = if (Test-Path -LiteralPath $Settings) {
    Get-Content -LiteralPath $Settings -Raw | ConvertFrom-Json
} else {
    [PSCustomObject]@{}
}
$b = Backup $Settings
if ($b) { Did "settings.json backed up to $(Split-Path -Leaf $b)" }

# Named hookMap, not hooks: PowerShell variable names are case-insensitive, so `$hooks` here
# would BE `$Hooks`, the hooks directory - and every path built from it afterwards would read
# "System.Collections.Specialized.OrderedDictionary\lea.js". Cost one bad settings.json to find.
$hookMap = [ordered]@{}
$hookMap.SessionStart = HookEntry ($node -f (Join-Path $Hooks 'lea.js')) 20 'startup|resume|clear|compact' 'Loading Lea...'
$hookMap.UserPromptSubmit = HookEntry ($node -f (Join-Path $Hooks 'shadow-enqueue.js')) 30 '' ''
$hookMap.Stop = HookEntry ($node -f (Join-Path $Hooks 'shadow-collect.js')) 30 '' ''
$s | Add-Member -NotePropertyName hooks -NotePropertyValue ([PSCustomObject]$hookMap) -Force
Did 'settings.json: SessionStart=lea.js, UserPromptSubmit=shadow-enqueue.js, Stop=shadow-collect.js'

# A session with plugins on is not the configuration being measured. Switched off, not
# uninstalled: the shadow arm's own cfg\modes.json turns caveman and ponytail back on for the
# one run that needs them, and it can only switch on a plugin the machine already has.
if (-not $KeepPlugins -and $s.PSObject.Properties['enabledPlugins']) {
    $on = @($s.enabledPlugins.PSObject.Properties | Where-Object { $_.Value -eq $true })
    if ($on.Count) {
        foreach ($p in $on) { $s.enabledPlugins.$($p.Name) = $false }
        Did "settings.json: $($on.Count) plugin(s) switched off - $(($on.Name) -join ', ')"
    } else { Skip 'no plugins were enabled' }
}

# The CLI's own description of this key: "When a claude.ai usage limit stops your session, wait
# for the limit to reset and continue the task automatically. When off, the limit dialog offers
# the wait as a choice instead." Low priority is NOT this and cannot be pre-set - it is offered by
# the server in the rate-limit response headers, so it exists only once a limit has been hit.
if (-not $NoAutoContinue) {
    if ($s.autoContinueAtUsageLimit -eq $true) { Skip 'autoContinueAtUsageLimit already on' }
    else {
        $s | Add-Member -NotePropertyName autoContinueAtUsageLimit -NotePropertyValue $true -Force
        Did 'settings.json: autoContinueAtUsageLimit on - the session resumes after a usage limit'
    }
}

if (-not $WhatIf) {
    $s | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Settings -Encoding utf8
}

# ---- what the target user will actually see -------------------------------------------------
Say ""
Say "Verify (as $((Split-Path -Leaf $TargetHome))):" 'Cyan'
Say "  the hooks read shadow-dir.txt at session start, so this takes effect on RESTART."
Say "  ledger rows from this profile will carry user=$(Split-Path -Leaf $TargetHome)."
if (-not $WhatIf) {
    $bad = @()
    foreach ($f in $Files) { if (-not (Test-Path (Join-Path $Hooks $f.To))) { $bad += $f.To } }
    if (-not (Test-Path $Ptr)) { $bad += 'shadow-dir.txt' }
    if ($bad.Count) { Fail "these did not land: $($bad -join ', ')" }
    try { $written = Get-Content -LiteralPath $Settings -Raw | ConvertFrom-Json }
    catch { Fail "settings.json is no longer valid JSON - restore $b" }
    # Valid JSON is not the same as correct JSON. Every command it names must exist on disk,
    # or the session starts with three hooks that quietly do nothing.
    foreach ($evt in @('SessionStart', 'UserPromptSubmit', 'Stop')) {
        $cmd = $written.hooks.$evt[0].hooks[0].command
        if ($cmd -notmatch '"([^"]+)"') { Fail "$evt hook command has no quoted path: $cmd" }
        if (-not (Test-Path -LiteralPath $Matches[1])) { Fail "$evt hook points at a file that does not exist: $($Matches[1])" }
    }
    Did 'all files present, settings.json parses, and every hook command resolves'
}
Say ""
