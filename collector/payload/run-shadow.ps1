# The shadow arm: answer the same prompt a second time, in a copy, with a stock config.
#
# Launched detached by the UserPromptSubmit hook, so it runs while Lea works on the real
# directory and never blocks the session. It writes only inside shadow\runs\<id>\.
#
# Two copies are made on purpose. base\ is the directory as it was when the prompt arrived, and
# it is never touched again - it is the common ancestor that makes the two answers comparable.
# work\ is where the shadow agent runs. Lea's own diff is taken later, at Stop, against that
# same base.
#
# The base copy is taken BEFORE the budget is checked. That ordering is what makes deferral
# honest: a prompt blocked by a budget is queued rather than lost, and when it finally runs it
# still starts from the tree Lea diverged from. Copying after the check would hand the retry a
# directory Lea had already edited, and the pair would mean nothing.
#
# Usage (the hook does this):
#   pwsh -NoProfile -File run-shadow.ps1 -Id <id> -PromptFile <path> -Cwd <path> -Model <model>
#                                        [-ModelGuess -Transcript <path>]

param(
    [Parameter(Mandatory = $true)][string]$Id,
    [Parameter(Mandatory = $true)][string]$PromptFile,
    [Parameter(Mandatory = $true)][string]$Cwd,
    # The model the session is running, so the shadow arm answers on the same one: otherwise the
    # comparison measures Opus against Sonnet, not config against config.
    [string]$Model = '',
    # Set when -Model could only be guessed from settings.json, which is the case on the first
    # prompt of a session: the transcript has no assistant record yet and nothing else on disk
    # carries the running model id. Nothing is billed or written under the guess: every exit
    # from this script resolves it first, or waits model_wait_seconds out and records in the log
    # that it could not.
    [switch]$ModelGuess,
    [string]$Transcript = '',
    # Set when this prompt opened its session. See pair_session_start_only in config.json:
    # a prompt sent mid-conversation cannot be answered by an arm that has no conversation,
    # so pairing one would compare two different problems.
    [switch]$SessionStart
)

$ErrorActionPreference = 'Continue'
[Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture

$PromptFile = (Resolve-Path -LiteralPath $PromptFile).Path
$Cwd = (Resolve-Path -LiteralPath $Cwd).Path

$Shadow = $PSScriptRoot
$RunDir = Join-Path $Shadow "runs\$Id"
$Csv = Join-Path $Shadow 'shadow.csv'
$Log = Join-Path $Shadow 'shadow.log'
$Lock = Join-Path $Shadow '.lock'
# Both resolved rather than hardcoded: this script ships to other machines and other users.
$BenchCfg = if (Test-Path (Join-Path $Shadow 'cfg')) { Join-Path $Shadow 'cfg' }
            else { Join-Path $HOME '.claude\bench\cfg' }
$Claude = @(
    'C:\Users\<name>\.local\bin\claude.exe',
    (Join-Path $HOME '.local\bin\claude.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\claude\claude.exe')
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $Claude) {
    # Not the PATH `claude` shim by preference - it drops flags after a multi-line prompt - but
    # better than not running at all.
    $Claude = (Get-Command claude -ErrorAction SilentlyContinue).Source
}
$Sep = [IO.Path]::DirectorySeparatorChar

$cfg = Get-Content (Join-Path $Shadow 'config.json') -Raw | ConvertFrom-Json

function Write-Log([string]$m) {
    "[{0}] {1} {2}" -f (Get-Date -Format 'MM-dd HH:mm:ss'), $Id, $m | Add-Content -Path $Log
}

function Write-Row([hashtable]$r) {
    if (-not (Test-Path $Csv)) {
        ('id,when,config,model,rule,status,cost_usd,turns,output_tokens,duration_s,' +
         'files_copied,note,input_tokens,cache_read_tokens') |
            Set-Content $Csv -Encoding utf8
    }
    $fields = @($r.id, $r.when, $r.config, $r.model, $r.rule, $r.status, $r.cost, $r.turns,
                $r.output, $r.duration, $r.files, $r.note, $r.input, $r.cacheRead) |
              ForEach-Object {
        $v = "$_"
        if ($v -match '[",]') { '"' + $v.Replace('"', '""') + '"' } else { $v }
    }
    ($fields -join ',') | Add-Content $Csv -Encoding utf8
}

function Get-Family([string]$m) {
    switch -Regex ($m) { 'opus' { 'opus' } 'haiku' { 'haiku' } default { 'sonnet' } }
}

# Is this plugin actually on this machine? Installed means on disk, not merely recorded:
# a pruned or hand-deleted cache leaves the entry in installed_plugins.json behind.
function Test-PluginInstalled([string]$name) {
    $rec = Join-Path $HOME '.claude\plugins\installed_plugins.json'
    if (-not (Test-Path $rec)) { return $false }
    try { $j = Get-Content $rec -Raw | ConvertFrom-Json } catch { return $false }
    $entry = $j.plugins.$name
    if (-not $entry) { return $false }
    foreach ($e in @($entry)) {
        if ($e.installPath -and (Test-Path -LiteralPath $e.installPath)) { return $true }
    }
    return $false
}

# The model the session is running, read from the newest assistant record in its transcript -
# the only place Claude Code writes the model id. Returns $null if none has been written yet.
#
# waitSeconds exists for the first prompt of a session, where that record appears only once the
# session's first assistant message lands. Polling for it is free: this process is detached, and
# the base copy is already taken, so nothing about the comparison drifts while it waits.
#
# The file is open for append by the session, so it is read with FileShare.ReadWrite; Get-Content
# would be enough on most days and would fail on the day the handle is exclusive. Only lines that
# mention a model are parsed - the transcript is mostly large assistant records.
function Resolve-SessionModel([string]$transcript, [int]$waitSeconds) {
    if (-not $transcript -or -not (Test-Path -LiteralPath $transcript)) { return $null }
    $deadline = (Get-Date).AddSeconds($waitSeconds)
    while ($true) {
        $lines = @()
        try {
            $fs = [IO.File]::Open($transcript, 'Open', 'Read', 'ReadWrite')
            try {
                $sr = New-Object IO.StreamReader($fs)
                $lines = $sr.ReadToEnd() -split "`n"
            }
            finally { $fs.Dispose() }
        }
        catch {}
        for ($i = $lines.Count - 1; $i -ge 0; $i--) {
            if ($lines[$i] -notlike '*"model"*') { continue }
            $rec = $null
            try { $rec = $lines[$i] | ConvertFrom-Json } catch { continue }
            if ($rec.message -and $rec.message.model) { return [string]$rec.message.model }
        }
        if ((Get-Date) -ge $deadline) { return $null }
        Start-Sleep -Seconds 2
    }
}

# Replace a guessed model with the session's real one. Every call site is a point where nothing
# is left to hold still: either the run is about to be skipped and no copy will ever be taken,
# or the copy is already on disk. So the wait inside can never shift the ancestor the two arms
# are compared on, and no row and no dollar goes out under a name that was only a guess.
function Update-RunModel {
    if (-not $script:modelIsGuess) { return }
    $m = Resolve-SessionModel $script:Transcript $script:ModelWait
    if ($m) {
        Write-Log "model from transcript: $m (guessed $($script:runModel))"
        $script:runModel = $m
    }
    else { Write-Log "model unresolved, keeping the guess $($script:runModel)" }
    $script:modelIsGuess = $false
}

# Returns the reason this run cannot go ahead right now, or $null if it can. Budget reasons are
# temporary - the caller defers on those; a usage limit is one too.
function Get-BlockReason([string]$model) {
    if (-not (Test-Path $Csv)) { return $null }
    $ledger = @(Import-Csv $Csv)
    $family = Get-Family $model

    $today = Get-Date -Format 'yyyy-MM-dd'
    $spentToday = ($ledger | Where-Object { $_.when -like "$today*" -and $_.cost_usd } |
                   Measure-Object -Property cost_usd -Sum).Sum
    if ($spentToday -ge $cfg.daily_budget_usd) {
        return "daily backstop reached (`$$([math]::Round($spentToday, 2)))"
    }

    $windowHours = if ($cfg.window_hours) { [double]$cfg.window_hours } else { 5 }
    $since = (Get-Date).AddHours(-$windowHours)
    $spentWindow = 0.0; $spentModel = 0.0
    foreach ($row in $ledger) {
        $when = [datetime]::MinValue
        if (-not [datetime]::TryParse($row.when, [ref]$when)) { continue }
        if ($when -lt $since) { continue }
        $c = 0.0
        if (-not [double]::TryParse($row.cost_usd, [ref]$c)) { continue }
        $spentWindow += $c
        if ($row.model -and (Get-Family $row.model) -eq $family) { $spentModel += $c }
    }
    $windowCap = if ($cfg.window_budget_usd) { [double]$cfg.window_budget_usd } else { 3 }
    if ($spentWindow -ge $windowCap) {
        return "window cap reached: `$$([math]::Round($spentWindow, 2)) in the last $windowHours h"
    }
    $perModel = $null
    if ($cfg.window_budget_by_model) { $perModel = $cfg.window_budget_by_model.$family }
    if ($perModel -and $spentModel -ge [double]$perModel) {
        return "$family share spent: `$$([math]::Round($spentModel, 2)) of `$$perModel in the last $windowHours h"
    }

    # A limit is a wall, not a hiccup: retrying against it spends turns and learns nothing.
    $pause = if ($cfg.pause_minutes_after_limit) { [double]$cfg.pause_minutes_after_limit } else { 60 }
    $cutoff = (Get-Date).AddMinutes(-$pause)
    foreach ($row in $ledger) {
        if ($row.status -ne 'limit') { continue }
        $when = [datetime]::MinValue
        if (-not [datetime]::TryParse($row.when, [ref]$when)) { continue }
        if ($when -ge $cutoff) {
            return "a usage limit was hit at $($when.ToString('HH:mm')) - standing down for $pause min"
        }
    }
    return $null
}

# Copy $from into $to, honouring the caps. Returns the file count, or -1 with $script:CopyWhy set.
function Copy-Tree([string]$from, [string]$to) {
    New-Item -ItemType Directory -Force -Path $to | Out-Null
    $excludeDirs = @($cfg.copy.exclude_dirs)
    $maxFileBytes = $cfg.copy.max_file_mb * 1MB
    $scanCap = if ($cfg.copy.max_scan_seconds) { [int]$cfg.copy.max_scan_seconds } else { 60 }
    $total = 0; $count = 0
    $script:CopyWhy = ''
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        foreach ($full in [IO.Directory]::EnumerateFiles($from, '*', [IO.SearchOption]::AllDirectories)) {
            if ($sw.Elapsed.TotalSeconds -gt $scanCap) { $script:CopyWhy = "the scan took over $scanCap s"; break }
            $rel = $full.Substring($from.Length).TrimStart($Sep)
            $parts = $rel.Split($Sep)
            $skip = $false
            foreach ($d in $excludeDirs) { if ($parts -contains $d) { $skip = $true; break } }
            if ($skip) { continue }
            $name = [IO.Path]::GetFileName($full)
            foreach ($g in $cfg.copy.exclude_globs) { if ($name -like $g) { $skip = $true; break } }
            if ($skip) { continue }
            $len = 0
            try { $len = (Get-Item -LiteralPath $full -Force).Length } catch { continue }
            if ($len -gt $maxFileBytes) { continue }
            $total += $len; $count++
            if ($total -gt ($cfg.copy.max_total_mb * 1MB)) { $script:CopyWhy = 'over the size cap'; break }
            if ($count -gt $cfg.copy.max_files) { $script:CopyWhy = 'over the file-count cap'; break }
            $dest = Join-Path $to $rel
            New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent) | Out-Null
            Copy-Item -LiteralPath $full -Destination $dest -Force -ErrorAction SilentlyContinue
        }
    }
    catch { $script:CopyWhy = "could not read the tree: $($_.Exception.Message)" }
    if ($script:CopyWhy) {
        Remove-Item $to -Recurse -Force -ErrorAction SilentlyContinue
        return -1
    }
    return $count
}

# Run one prepared cell: pick the config, answer the prompt in a copy of base, record both.
function Invoke-Cell([string]$cellId, [string]$dir, [string]$model, [int]$files) {
    $prompt = Get-Content (Join-Path $dir 'prompt.txt') -Raw
    $now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $base = Join-Path $dir 'base'
    $work = Join-Path $dir 'work'
    if (Test-Path $work) { Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue }
    Copy-Item $base $work -Recurse -Force

    $pickFile = Join-Path $dir 'pick.json'
    if (Test-Path $pickFile) {
        $pk = Get-Content $pickFile -Raw | ConvertFrom-Json
        $config = $pk.config; $rule = $pk.rule
    }
    else {
        $picked = & python (Join-Path $Shadow 'pick.py') $prompt 2>$null
        $picks = "$picked".Trim() -split "`t", 3
        $config = if ($picks[0]) { $picks[0] } else { 'bare' }
        $rule = if ($picks.Count -gt 1) { $picks[1] } else { 'picker failed -> bare' }
    }
    $settings = Join-Path $BenchCfg "$config.json"
    if (-not (Test-Path $settings)) {
        # modes needs two plugins installed; bare needs nothing. On a machine without them the
        # comparison is still valid, just against bare - and the row says which it was.
        $fallback = Join-Path $BenchCfg 'bare.json'
        if ($config -ne 'bare' -and (Test-Path $fallback)) {
            $rule = "$rule [no $config.json on this machine -> fell back to bare]"
            $config = 'bare'; $settings = $fallback
        }
        else {
            Write-Row @{ id = $cellId; when = $now; config = $config; model = $model; rule = $rule
                         status = 'error'; note = "no settings file at $settings" }
            return
        }
    }

    # `enabledPlugins` is a switch, not a fetch: it can only turn on a plugin the machine
    # already has. A config that names plugins this machine has never installed therefore runs
    # as plain `bare` - and recording that as `modes` is the one failure a benchmark cannot
    # survive, because the row looks like evidence. Same fallback as a missing settings file,
    # same visible note, so the pool can see which machines had the plugins and which did not.
    $absent = @()
    try {
        $sj = Get-Content $settings -Raw | ConvertFrom-Json
        if ($sj.enabledPlugins) {
            foreach ($p in $sj.enabledPlugins.PSObject.Properties) {
                if ($p.Value -eq $true -and -not (Test-PluginInstalled $p.Name)) { $absent += $p.Name }
            }
        }
    }
    catch {}
    if ($absent.Count) {
        $why = "$($absent -join ', ') not installed on this machine"
        $fallback = Join-Path $BenchCfg 'bare.json'
        if ($config -ne 'bare' -and (Test-Path $fallback)) {
            $rule = "$rule [$why -> fell back to bare]"
            $config = 'bare'; $settings = $fallback
            Write-Log "config downgraded to bare: $why"
        }
        else {
            Write-Row @{ id = $cellId; when = $now; config = $config; model = $model; rule = $rule
                         status = 'error'; note = $why }
            return
        }
    }

    "[{0}] {1} running {2} on {3} ({4} files)" -f (Get-Date -Format 'MM-dd HH:mm:ss'), $cellId,
        $config, $model, $files | Add-Content -Path $Log
    $t0 = Get-Date
    $out = Join-Path $dir 'result.json'
    $err = Join-Path $dir 'stderr.txt'
    $promptPath = Join-Path $dir 'prompt.txt'
    $callArgs = @(
        '-p'
        '--settings', $settings
        '--setting-sources', 'project'
        '--model', $model
        '--output-format', 'json'
        '--permission-mode', 'bypassPermissions'
        '--max-budget-usd', "$($cfg.budget_usd_per_run)"
    ) | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { "$_" } }

    Push-Location $work
    $proc = Start-Process $Claude -PassThru -NoNewWindow -RedirectStandardInput $promptPath `
        -RedirectStandardOutput $out -RedirectStandardError $err -ArgumentList $callArgs
    $proc.WaitForExit()
    Pop-Location
    $secs = [math]::Round(((Get-Date) - $t0).TotalSeconds, 0)

    $cost = ''; $turns = ''; $outTok = ''; $status = 'error'; $note = ''
    # What this arm had to read to answer. Recorded because the other arm's figure is not
    # comparable to it: a turn inside a long session re-reads the whole conversation, and a
    # shadow run reads only its own. Without both numbers the cost ratio looks like a verdict
    # about the configuration when it is mostly a verdict about how far in the prompt arrived.
    $inTok = ''; $crTok = ''
    try {
        $j = Get-Content $out -Raw | ConvertFrom-Json
        $cost = $j.total_cost_usd; $turns = $j.num_turns; $outTok = $j.usage.output_tokens
        $inTok = [int]$j.usage.input_tokens + [int]$j.usage.cache_creation_input_tokens
        $crTok = [int]$j.usage.cache_read_input_tokens
        # A run stopped by the budget is not a cheap result, it is an unfinished one. Its own
        # status keeps it out of every comparison.
        if ($j.subtype -eq 'error_max_budget_usd') {
            $status = 'truncated'
            $note = "cut off by the `$$($cfg.budget_usd_per_run) per-run cap - the task is bigger than the shadow budget"
        }
        elseif ($j.is_error) { $status = 'error'; $note = "agent reported is_error ($($j.subtype))" }
        else { $status = 'ok' }
    }
    catch {
        $note = 'could not parse result.json'
        $blob = Get-Content $err -Raw -ErrorAction SilentlyContinue
        if ($blob -match 'usage limit|session limit') { $status = 'limit'; $note = 'usage limit' }
    }

    # git diff --no-index turns two directories into one reviewable patch, no repo needed.
    & git diff --no-index --binary -- $base $work 2>$null |
        Set-Content (Join-Path $dir 'shadow.patch') -Encoding utf8
    Remove-Item (Join-Path $dir 'deferred.json') -Force -ErrorAction SilentlyContinue

    Write-Row @{ id = $cellId; when = $now; config = $config; model = $model; rule = $rule
                 status = $status; cost = $cost; turns = $turns; output = $outTok
                 duration = $secs; files = $files; note = $note
                 input = $inTok; cacheRead = $crTok }
    "[{0}] {1} {2} cost={3} turns={4} {5}s" -f (Get-Date -Format 'MM-dd HH:mm:ss'), $cellId,
        $status, $cost, $turns, $secs | Add-Content -Path $Log
}

# ---------------------------------------------------------------------------- main
if (-not $cfg.enabled) { Write-Log 'disabled in config.json'; exit 0 }

$prompt = Get-Content $PromptFile -Raw
$now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
# A pinned config.model beats anything the hook worked out - that is what pinning means.
$modelPinned = $cfg.model -and $cfg.model -ne 'match'
$runModel = if ($modelPinned) { [string]$cfg.model } elseif ($Model) { $Model } else { 'sonnet' }
# Try the transcript once before the cheap skips. When the record is already there this costs a
# single read and keeps even the skipped rows spelling the model the way the ledger groups by.
$modelIsGuess = $ModelGuess.IsPresent -and -not $modelPinned
$ModelWait = if ($cfg.model_wait_seconds) { [int]$cfg.model_wait_seconds } else { 90 }

# Permanent skips first - these never become worth retrying, so they cost no copy.
if ($prompt.Trim().Length -lt $cfg.min_prompt_chars) {
    Update-RunModel
    Write-Row @{ id = $Id; when = $now; model = $runModel; status = 'skipped'
                 note = 'prompt shorter than min_prompt_chars' }
    exit 0
}
foreach ($pat in $cfg.skip_prompt_patterns) {
    if ($prompt.Trim() -match $pat) {
        Update-RunModel
        Write-Row @{ id = $Id; when = $now; model = $runModel; status = 'skipped'
                     note = "matched skip pattern $pat" }
        exit 0
    }
}
# Before the copy, because this one can never become worth retrying. A prompt sent into an
# existing conversation means what the conversation made it mean; the shadow arm starts from
# nothing and answers a different question, at full price. Five such runs cost $5.74 here and
# produced no comparison at all.
if ($cfg.pair_session_start_only -and -not $SessionStart) {
    Update-RunModel
    Write-Row @{ id = $Id; when = $now; model = $runModel; status = 'skipped'
                 note = 'sent mid-conversation - the shadow arm has no conversation to resolve it against' }
    exit 0
}
# Decide the config before anything is copied, because the decision says whether a copy is
# needed at all: a prose question is answered in the reply, so neither arm touches the
# directory and the shadow can answer it anywhere - including from a home-directory session,
# which would otherwise contribute nothing.
$picked = & python (Join-Path $Shadow 'pick.py') $prompt 2>$null
$picks = "$picked".Trim() -split "`t", 3
$pickConfig = if ($picks[0]) { $picks[0] } else { 'bare' }
$pickRule = if ($picks.Count -gt 1) { $picks[1] } else { 'picker failed -> bare' }
$needsTree = -not ($picks.Count -gt 2 -and $picks[2] -eq 'notree')

$HomeFull = [IO.Path]::GetFullPath($HOME).TrimEnd($Sep)
$CwdFull = [IO.Path]::GetFullPath($Cwd).TrimEnd($Sep)
if ($needsTree -and ($CwdFull -eq $HomeFull -or $HomeFull.StartsWith($CwdFull + $Sep))) {
    Update-RunModel
    Write-Row @{ id = $Id; when = $now; config = $pickConfig; model = $runModel; rule = $pickRule
                 status = 'skipped'
                 note = 'agentic prompt in the home directory - the tree is the experiment, and this one cannot be copied' }
    exit 0
}

# One shadow run at a time: a second would race for the same quota and distort both.
$lockStream = $null
try { $lockStream = [IO.File]::Open($Lock, 'OpenOrCreate', 'ReadWrite', 'None') }
catch {
    Update-RunModel
    Write-Row @{ id = $Id; when = $now; model = $runModel; status = 'skipped'
                 note = 'another shadow run is in flight' }
    exit 0
}

try {
    New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
    $kept = Join-Path $RunDir 'prompt.txt'
    if ($PromptFile -ne $kept) { Copy-Item $PromptFile $kept -Force }

    @{ config = $pickConfig; rule = $pickRule; needsTree = $needsTree } | ConvertTo-Json |
        Set-Content (Join-Path $RunDir 'pick.json') -Encoding utf8

    if ($needsTree) {
        $files = Copy-Tree $CwdFull (Join-Path $RunDir 'base')
        if ($files -lt 0) {
            Update-RunModel
            Write-Row @{ id = $Id; when = $now; config = $pickConfig; model = $runModel
                         rule = $pickRule; status = 'skipped'; note = $script:CopyWhy }
            Write-Log "skipped: $script:CopyWhy"
            exit 0
        }
    }
    else {
        # An empty ancestor: both arms answer in the reply, so there is nothing to diff and
        # nothing to copy. The patches come out empty, which is the correct record.
        New-Item -ItemType Directory -Force -Path (Join-Path $RunDir 'base') | Out-Null
        $files = 0
    }

    # The last point where the model can still be corrected: after this it is either spent under
    # a model name or recorded in the ledger as one. The ancestor copy is on disk already, so
    # waiting here cannot change what the two arms are compared on.
    Update-RunModel

    $blocked = Get-BlockReason $runModel
    if ($blocked) {
        if ($cfg.defer_when_over_budget) {
            # Queued, not lost. base\ is already the ancestor, so this stays comparable whenever
            # it runs; the next run with budget to spare drains it oldest-first.
            @{ id = $Id; model = $runModel; files = $files; at = (Get-Date).ToString('o'); why = $blocked } |
                ConvertTo-Json | Set-Content (Join-Path $RunDir 'deferred.json') -Encoding utf8
            Write-Row @{ id = $Id; when = $now; model = $runModel; status = 'deferred'
                         files = $files; note = "queued: $blocked" }
            Write-Log "deferred: $blocked"
        }
        else {
            Write-Row @{ id = $Id; when = $now; model = $runModel; status = 'skipped'; note = $blocked }
        }
        exit 0
    }

    Invoke-Cell $Id $RunDir $runModel $files

    # ---- drain the queue while there is budget left --------------------------------------
    $maxAge = if ($cfg.defer_max_age_hours) { [double]$cfg.defer_max_age_hours } else { 24 }
    $queueCap = if ($cfg.defer_max_queue) { [int]$cfg.defer_max_queue } else { 10 }
    $queued = @(Get-ChildItem (Join-Path $Shadow 'runs') -Directory -ErrorAction SilentlyContinue |
                Where-Object { Test-Path (Join-Path $_.FullName 'deferred.json') } |
                Sort-Object Name)
    # Oldest first, but never more than the cap: a backlog older than the cap is stale evidence.
    if ($queued.Count -gt $queueCap) {
        foreach ($old in $queued[0..($queued.Count - $queueCap - 1)]) {
            Write-Row @{ id = $old.Name; when = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); status = 'dropped'
                         note = "queue longer than defer_max_queue ($queueCap)" }
            Remove-Item $old.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
        $queued = $queued[($queued.Count - $queueCap)..($queued.Count - 1)]
    }
    foreach ($q in $queued) {
        $meta = Get-Content (Join-Path $q.FullName 'deferred.json') -Raw | ConvertFrom-Json
        $age = ((Get-Date) - [datetime]::Parse($meta.at)).TotalHours
        if ($age -gt $maxAge) {
            Write-Row @{ id = $q.Name; when = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); model = $meta.model
                         status = 'dropped'; note = "queued $([math]::Round($age,1)) h ago, past defer_max_age_hours" }
            Remove-Item $q.FullName -Recurse -Force -ErrorAction SilentlyContinue
            continue
        }
        $stop = Get-BlockReason $meta.model
        if ($stop) { Write-Log "drain stopped: $stop"; break }
        Write-Log "draining $($q.Name) (queued $([math]::Round($age,1)) h ago)"
        Invoke-Cell $q.Name $q.FullName $meta.model ([int]$meta.files)
    }
}
finally {
    if ($lockStream) { $lockStream.Close(); Remove-Item $Lock -Force -ErrorAction SilentlyContinue }
}
