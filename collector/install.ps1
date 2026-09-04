# Install the Lea collector: run Lea, and let a shadow arm answer every prompt a second time in
# the background so the two can be compared.
#
# What this touches, and nothing else:
#   ~/.claude/hooks/          three hook files, the hidden launcher, and lea.js
#   ~/.claude/shadow/         the runner, the picker, the report, the ledgers, the run copies
#   ~/.claude/shadow-dir.txt  a one-line pointer so the hooks can find that directory
#   ~/.claude/settings.json   three hook entries and autoContinueAtUsageLimit, merged - the file
#                             is backed up first. The toggle makes a session that hits the
#                             5-hour usage limit wait for the reset and carry on instead of
#                             ending; -NoAutoContinue leaves it alone.
#   ~/.claude/plugins/        caveman and ponytail, which cfg/modes.json switches on. They are
#                             installed and left DISABLED, so your own sessions are unchanged
#
# Nothing is sent anywhere. Data leaves this machine only when you run export.ps1 yourself.
#
# Usage:  pwsh -NoProfile -File install.ps1 [-Account <label>] [-InstallsOnThisAccount <n>]
#                                           [-ProjectRoot <dir>] [-SkipLea] [-SkipPlugins]
#                                           [-NoAutoContinue] [-Force]
#
# -ProjectRoot is what makes it not matter which directory you start `claude` in: when the
# session's own directory cannot be copied, the shadow arm uses the first of these that fits
# instead of skipping the prompt. Several go in COMMA-SEPARATED, not as a repeated flag -
# PowerShell binds an array once:  -ProjectRoot C:\src\app,C:\src\other
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
    # Do not install the plugins cfg/modes.json names. The shadow arm then has no non-bare
    # column at all: every prompt it would have answered as `modes` is answered as `bare`,
    # and the ledger's rule column says why. Nothing breaks; the account is just thinner.
    [switch]$SkipPlugins,
    # Directories to fall back to when the session's own working directory cannot be copied - a
    # home directory, or any tree over the caps in config.json. First one that fits wins.
    # Without it such a prompt is skipped, and since only the first prompt of a session can be
    # paired at all, that is a whole session contributing nothing rather than one prompt.
    # COMMA-SEPARATED, not a repeated flag: PowerShell binds an array once and rejects the second.
    #   -ProjectRoot C:\src\my-app,C:\src\other
    [string[]]$ProjectRoot = @(),
    # Leave autoContinueAtUsageLimit as you had it. On by default because a session that ends at
    # the 5-hour limit loses that prompt's measurement: the shadow arm's row is already written
    # and Lea's turn never is, so the pair is half-recorded rather than merely late.
    [switch]$NoAutoContinue,
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
# Installed means on disk, not merely recorded: a pruned cache leaves the entry behind.
function PluginInstalled([string]$name) {
    $rec = Join-Path $claudeDir 'plugins\installed_plugins.json'
    if (-not (Test-Path $rec)) { return $false }
    try { $j = Get-Content $rec -Raw | ConvertFrom-Json } catch { return $false }
    $entry = $j.plugins.$name
    if (-not $entry) { return $false }
    foreach ($e in @($entry)) {
        if ($e.installPath -and (Test-Path -LiteralPath $e.installPath)) { return $true }
    }
    return $false
}

Say ''
Say '  Lea collector' Cyan
Say '  -------------' Cyan

# ---- prerequisites, each named rather than assumed -------------------------------------
$missing = @()
if ($PSVersionTable.PSVersion.Major -lt 7) { $missing += 'PowerShell 7 (pwsh)' }
foreach ($tool in 'node', 'python', 'git') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { $missing += $tool }
}
# The first entry used to be one machine's absolute path, with a user name in it. That is two
# faults in a file other people install: it names somebody, and it is dead everywhere else.
# The remaining candidates are relative to whoever is running, which is what they should have
# been - and PATH catches the rest.
$claudeExe = @(
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

# ---- an install that would orphan an existing ledger stops here ---------------------------
# The hooks find the shadow directory through shadow-dir.txt, and this script points that file
# at ~/.claude/shadow. If it already names a different directory that exists, the machine is
# collecting somewhere else - into a project, say - and installing over it would leave those
# rows behind with nothing writing to them. Better to say so than to silently start again.
$pointer = Join-Path $claudeDir 'shadow-dir.txt'
if ((Test-Path $pointer) -and -not $Force) {
    $already = (Get-Content $pointer -Raw -ErrorAction SilentlyContinue).Trim()
    if ($already -and $already -ne $shadowDir -and (Test-Path $already)) {
        Fail ("a shadow directory is already registered at $already - installing here would " +
              "point the hooks at $shadowDir and orphan that ledger. Re-run with -Force if " +
              "that is what you want.")
    }
}

# ---- files ------------------------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $hooksDir, $shadowDir | Out-Null
foreach ($f in 'shadow-enqueue.js', 'shadow-collect.js', 'shadow-hidden-launch.vbs', 'statusline.ps1') {
    Copy-Item (Join-Path $payload $f) (Join-Path $hooksDir $f) -Force
}
foreach ($f in 'run-shadow.ps1', 'lib.ps1', 'pick.py', 'report.py', 'counter.py', 'migrate_ledgers.py') {
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
    if ($ProjectRoot.Count) {
        # Checked here rather than trusted: a root that does not exist would be a silent no-op at
        # the one moment it was supposed to save the session's only pairable prompt.
        $roots = @()
        foreach ($p in $ProjectRoot) {
            $full = ''
            try { $full = [IO.Path]::GetFullPath($p).TrimEnd([IO.Path]::DirectorySeparatorChar) } catch {}
            if ($full -and (Test-Path -LiteralPath $full)) { $roots += $full }
            elseif ($p -match ',') {
                # The commas survived into one string, so it was quoted: "-ProjectRoot 'a,b'" is
                # one path named a,b. Unquoted is what makes PowerShell bind it as two.
                Say "  -ProjectRoot got one quoted string containing commas, so it read as a single" Yellow
                Say "    path that does not exist. Drop the quotes: -ProjectRoot C:\a,C:\b" Yellow
            }
            else { Say "  -ProjectRoot $p does not exist - not added" Yellow }
        }
        $conf | Add-Member -NotePropertyName project_roots -NotePropertyValue $roots -Force
        if ($roots.Count) { Say "  project_roots: $($roots -join '; ')" Green }
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

# ---- the backup comes first, because the next step lets the CLI write here too -------------
if (Test-Path $settingsPath) {
    $backup = "$settingsPath.before-lea-collector-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Copy-Item $settingsPath $backup -Force
    Say "  settings.json backed up to $(Split-Path $backup -Leaf)" Green
}

# What was already yours, so the plugin step can hand it back exactly as it found it.
$preMarkets = @{}; $prePlugins = @{}
if (Test-Path $settingsPath) {
    $pre = Get-Content $settingsPath -Raw | ConvertFrom-Json
    if ($pre.extraKnownMarketplaces) {
        foreach ($m in $pre.extraKnownMarketplaces.PSObject.Properties) { $preMarkets[$m.Name] = $true }
    }
    if ($pre.enabledPlugins) {
        foreach ($p in $pre.enabledPlugins.PSObject.Properties) { $prePlugins[$p.Name] = $p.Value }
    }
}

# ---- the plugins the shadow arm's own configs name -----------------------------------------
# cfg/modes.json switches on caveman and ponytail. `enabledPlugins` is a switch, not a fetch: it
# can only turn on a plugin the machine already has, so without them that config runs as plain
# `bare`. The runner refuses to call that `modes` - it falls back and says so - which leaves an
# install with no non-bare column at all. Installing them here is what keeps that column real.
#
# They are installed and then left DISABLED for your own sessions. The shadow arm passes
# cfg/modes.json through --settings, which carries its own marketplace list and switches them on
# for that one run; your sessions have to stay Lea alone, or the arm being measured is not Lea.
# Measured on the machine this came from: leaving caveman's marketplace known to your settings
# adds seven skills to every session's context, about 310 tokens, whether the plugin is on or not.
$needMarkets = @{}; $needPlugins = @{}
foreach ($f in Get-ChildItem (Join-Path $shadowDir 'cfg') -Filter *.json) {
    $j = Get-Content $f.FullName -Raw | ConvertFrom-Json
    if ($j.enabledPlugins) {
        foreach ($p in $j.enabledPlugins.PSObject.Properties) {
            if ($p.Value -eq $true) { $needPlugins[$p.Name] = $true }
        }
    }
    if ($j.extraKnownMarketplaces) {
        foreach ($m in $j.extraKnownMarketplaces.PSObject.Properties) {
            # An owner/repo shorthand is resolved over SSH, and a machine that has never
            # connected to GitHub over SSH cannot clone it: "SSH host key is not in your
            # known_hosts file". That is every fresh machine. The HTTPS URL needs no key and
            # no credential for a public repo, so a url wins and a repo is turned into one.
            $src = $m.Value.source
            $needMarkets[$m.Name] = if ($src.url) { $src.url }
                                    elseif ($src.repo) { "https://github.com/$($src.repo).git" }
                                    else { "$src" }
        }
    }
}

$claudeCmd = if ($claudeExe) { $claudeExe } else { (Get-Command claude).Source }
$pluginReport = @()
if ($SkipPlugins) {
    Say '  -SkipPlugins: every shadow run will be bare, and will say so in the ledger' Yellow
}
elseif ($needPlugins.Count) {
    foreach ($name in @($needMarkets.Keys)) {
        # Adding a marketplace that is already known exits non-zero. That is not a failure.
        try { & $claudeCmd plugin marketplace add $needMarkets[$name] 2>&1 | Out-Null } catch {}
    }
    foreach ($p in @($needPlugins.Keys)) {
        if (-not (PluginInstalled $p)) {
            Say "  installing $p ..."
            try { & $claudeCmd plugin install $p -y --scope user 2>&1 | Out-Null } catch {}
        }
        $ok = PluginInstalled $p
        $pluginReport += @{ name = $p; ok = $ok }
        if ($ok) { Say "  $p installed" Green } else { Say "  x $p did not install" Yellow }
    }
}

# ---- settings.json, merged ------------------------------------------------------------------
# Read again rather than from before: the plugin step let the CLI write to this file.
$settings = [ordered]@{}
if (Test-Path $settingsPath) {
    $existing = Get-Content $settingsPath -Raw | ConvertFrom-Json
    foreach ($p in $existing.PSObject.Properties) { $settings[$p.Name] = $p.Value }
}

# Hand your own configuration back. The plugins stay installed - the shadow arm needs them on
# disk - but a marketplace this script added is removed again, and a plugin it installed is left
# off, so your sessions load exactly what they loaded before this ran.
if ($settings['extraKnownMarketplaces']) {
    $keep = [ordered]@{}
    foreach ($m in $settings['extraKnownMarketplaces'].PSObject.Properties) {
        if ($preMarkets[$m.Name] -or -not $needMarkets.ContainsKey($m.Name)) { $keep[$m.Name] = $m.Value }
    }
    if ($keep.Count) { $settings['extraKnownMarketplaces'] = $keep }
    else { $settings.Remove('extraKnownMarketplaces') }
}
if ($settings['enabledPlugins']) {
    $keep = [ordered]@{}
    foreach ($p in $settings['enabledPlugins'].PSObject.Properties) {
        if ($prePlugins.ContainsKey($p.Name)) { $keep[$p.Name] = $prePlugins[$p.Name] }
        elseif ($needPlugins.ContainsKey($p.Name)) { $keep[$p.Name] = $false }
        else { $keep[$p.Name] = $p.Value }
    }
    $settings['enabledPlugins'] = $keep
}

$hooks = [ordered]@{}
if ($settings['hooks']) {
    foreach ($p in $settings['hooks'].PSObject.Properties) { $hooks[$p.Name] = $p.Value }
}
# The leading comma is load-bearing. A PowerShell function unwraps a one-element array on the
# way out, so `return @(@{...})` hands back the hashtable itself and ConvertTo-Json then writes
# `"SessionStart": { ... }` where Claude Code expects a list of matcher groups. `,@(...)` wraps
# it once more, and the unwrapping leaves the intended array.
function HookEntry([string]$file, [int]$timeout, [string]$matcher) {
    $cmd = @{ type = 'command'; command = "node `"$(Join-Path $hooksDir $file)`""; timeout = $timeout }
    if ($matcher) { return ,@(@{ matcher = $matcher; hooks = @($cmd) }) }
    return ,@(@{ hooks = @($cmd) })
}
if (-not $SkipLea) {
    $hooks['SessionStart'] = HookEntry 'lea.js' 20 'startup|resume|clear|compact'
}
# 30 s, not the 10 and 20 these used to be. Both hooks read the session transcript, which grows
# without bound as a conversation goes on, and a "UserPromptSubmit hook timed out after 10s -
# output discarded" is a silently lost measurement. The enqueue hook's own read is bounded now
# (one window from the end rather than two full reads), so the headroom is only headroom.
$hooks['UserPromptSubmit'] = HookEntry 'shadow-enqueue.js' 30 ''
$hooks['Stop'] = HookEntry 'shadow-collect.js' 30 ''
$settings['hooks'] = $hooks

# A session that dies at the 5-hour limit takes its measurement with it: the shadow arm's row is
# already written, Lea's turn is not. This makes the session wait for the reset and carry on. The
# CLI's own description: "When a claude.ai usage limit stops your session, wait for the limit to
# reset and continue the task automatically. When off, the limit dialog offers the wait as a
# choice instead." Low priority is NOT this and cannot be pre-set - it is offered by the server in
# the rate-limit response headers, so it exists only once a limit has been hit.
if (-not $NoAutoContinue) {
    $settings['autoContinueAtUsageLimit'] = $true
}

# The statusline, and only if the profile has none. It shows the directory, the model, whether
# the shadow arm will act on this session, and the count of pairs that can carry a ratio - the
# number that decides whether the savings figure may stop being a projection. Worth having where
# it is seen without being asked for.
#
# Never overwritten. A statusline is a personal thing and someone who already has one has chosen
# it; replacing it would be the installer deciding something that is not its business. Said out
# loud either way, so a profile that ends up without the badge knows why.
if ($settings['statusLine']) {
    Say "  statusline left alone - this profile already has one" Yellow
    Say "    to show the pair counter, add a segment that reads shadow\counter.json" Gray
}
else {
    $settings['statusLine'] = @{
        type    = 'command'
        command = "pwsh -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $hooksDir 'statusline.ps1')`""
    }
}

$settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding utf8
Say '  settings.json updated (hooks merged, everything else left alone)' Green
if (-not $NoAutoContinue) { Say '  autoContinueAtUsageLimit on - the session resumes after a usage limit' Green }

Say ''
Say '  Checklist' Cyan
function Item([bool]$ok, [string]$label, [string]$fix) {
    if ($ok) { Say "   [x] $label" Green }
    else { Say "   [ ] $label"; Say "       fix: $fix" Yellow }
}
Item (Test-Path (Join-Path $hooksDir 'shadow-enqueue.js')) 'shadow hooks installed' 'run install.ps1 again'
Item ($SkipLea -or (Test-Path $leaTarget)) 'Lea hook installed' 'run install.ps1 without -SkipLea'
Item (Test-Path $cfgPath) 'config.json with your budgets' 'run install.ps1 -Force'
Item ((Get-Content (Join-Path $claudeDir 'shadow-dir.txt') -Raw -EA SilentlyContinue).Trim() -eq $shadowDir) `
     'the hooks know where the shadow directory is' "write $shadowDir into $claudeDir\shadow-dir.txt"
if ($SkipPlugins) {
    Item $false 'the modes column (skipped by request)' 'run install.ps1 without -SkipPlugins'
}
else {
    foreach ($r in $pluginReport) {
        Item $r.ok "$($r.name) installed - the modes column needs it" "claude plugin install $($r.name) -y"
    }
}
Say ''
Say '  Two steps only you can do:' Cyan
Say '   [ ] Restart Claude Code. The banner should start with LEA ACTIVE.'
# What the second step is depends on whether project_roots was filled: with it, where you start
# no longer decides anything, and telling you otherwise would send you chasing a rule that is not
# there any more.
$configuredRoots = @()
try { $configuredRoots = @((Get-Content $cfgPath -Raw | ConvertFrom-Json).project_roots).Where({ $_ }) } catch {}
if ($configuredRoots.Count) {
    Say '   [ ] Nothing about directories - project_roots is set, so a session opened anywhere'
    Say '       still contributes. A working directory that cannot be copied falls back to'
    Say "       $($configuredRoots[0]),"
    Say '       and the row records that the two arms started from different trees.'
}
else {
    Say '   [ ] Work from a project directory, or set project_roots in config.json. A prompt whose'
    Say '       working directory cannot be copied is skipped, and since only the first prompt of'
    Say '       a session can be paired, that costs the whole session. Questions answered in the'
    Say '       reply need no directory at all and always run.'
}
Say ''
Say "   See what has been collected:  python `"$shadowDir\report.py`""
Say "   Package it to send back:      pwsh -File `"$shadowDir\export.ps1`""
Say "   Stop collecting:              set enabled to false in $cfgPath"
Say ''
