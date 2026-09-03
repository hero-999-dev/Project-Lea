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
$Sep = [IO.Path]::DirectorySeparatorChar

# Loaded before the CLI is resolved, because the resolution now reads a key out of it.
$cfg = Get-Content (Join-Path $Shadow 'config.json') -Raw | ConvertFrom-Json

# config.json's `claude_path` first, for a machine where the binary is not under the profile
# running the hooks - which is the case here, and used to be a hardcoded absolute path with a
# user name in it. That is two faults in a file other people install: it names somebody, and it
# is dead on every other machine. A config key says the same thing without shipping it.
$Claude = @(
    $cfg.claude_path,
    (Join-Path $HOME '.local\bin\claude.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\claude\claude.exe')
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $Claude) {
    # Not the PATH `claude` shim by preference - it drops flags after a multi-line prompt - but
    # better than not running at all.
    $Claude = (Get-Command claude -ErrorAction SilentlyContinue).Source
}

# Shared with the tests, so neither side has to build code from text. See lib.ps1.
. (Join-Path $PSScriptRoot 'lib.ps1')

# One shadow run at a time PER ACCOUNT, not per ledger. The lock exists because two runs on one
# account race for the same 5-hour usage window and distort each other's rows - which is not true
# of two runs on different accounts, and making those queue behind one another throws away a pair
# for nothing. Same rule as the budget, read off the same map.
$AccountLabel = Get-AccountLabel
if ($AccountLabel) {
    $Lock = Join-Path $Shadow ".lock-$($AccountLabel -replace '[^A-Za-z0-9_-]', '_')"
}

function Write-Log([string]$m) {
    "[{0}] {1} {2}" -f (Get-Date -Format 'MM-dd HH:mm:ss'), $Id, $m | Add-Content -Path $Log
}

# Two Windows users on one machine can point at one shadow directory, so two processes can be
# writing here at once. A torn row is the one thing a ledger cannot survive, so the append takes
# a lock file - the Node Stop hook takes the same one, by the same name.
$LedgerLock = Join-Path $Shadow '.ledger.lock'

function Add-LineLocked([string]$Path, [string]$Line) {
    $held = $null
    $deadline = (Get-Date).AddSeconds(3)
    while ((Get-Date) -lt $deadline) {
        try { $held = [IO.File]::Open($LedgerLock, 'CreateNew', 'Write', 'None'); break } catch {}
        # A lock older than the longest write anyone here does is a crashed writer, not a busy one.
        try {
            if (((Get-Date) - (Get-Item $LedgerLock).LastWriteTime).TotalSeconds -gt 10) {
                Remove-Item $LedgerLock -Force -ErrorAction SilentlyContinue
            }
        } catch {}
        Start-Sleep -Milliseconds 25
    }
    try { $Line | Add-Content $Path -Encoding utf8 }
    finally {
        if ($held) { $held.Dispose(); Remove-Item $LedgerLock -Force -ErrorAction SilentlyContinue }
    }
}

# `user` and `host` are not bookkeeping: with two installs writing one ledger, a row that does
# not say who wrote it cannot be told apart from one written under a different account, budget
# or model, and a difference between installs would read as a difference between configs.
# tree_root is the directory the shadow arm actually copied. It is usually the session's cwd, and
# when it is not, that is exactly what a reader has to know: report.py compares it against Lea's
# own cwd and keeps pairs whose arms started from different trees apart from the ones that did not.
$CsvHeader = 'id,when,config,model,rule,status,cost_usd,turns,output_tokens,duration_s,' +
             'files_copied,note,input_tokens,cache_read_tokens,user,host,tree_root'

function Write-Row([hashtable]$r) {
    if (-not (Test-Path $Csv)) { $CsvHeader | Set-Content $Csv -Encoding utf8 }
    $fields = @($r.id, $r.when, $r.config, $r.model, $r.rule, $r.status, $r.cost, $r.turns,
                $r.output, $r.duration, $r.files, $r.note, $r.input, $r.cacheRead,
                $env:USERNAME, $env:COMPUTERNAME, $r.treeRoot) |
              ForEach-Object {
        $v = "$_"
        if ($v -match '[",]') { '"' + $v.Replace('"', '""') + '"' } else { $v }
    }
    Add-LineLocked $Csv ($fields -join ',')
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
            if (-not ($rec.message -and $rec.message.model)) { continue }
            # "<synthetic>" is Claude Code's own injected record - a notice, not an answer, and
            # not a model id anything can be run with. The enqueue hook already skips it; this
            # reader did not, and wrote `model=<synthetic>` into a real ledger row on
            # 2026-09-02. Keep looking backwards for a real one.
            $m = [string]$rec.message.model
            if ($m -match '^claude-') { return $m }
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


function Get-BlockReason([string]$model) {
    if (-not (Test-Path $Csv)) { return $null }
    $ledger = @(Import-Csv $Csv)
    # One ledger can hold two installs. The budget is a property of the usage window, and the
    # window belongs to the Anthropic account - so spend is counted per account, not per file.
    # A row with no user predates the column, and on that machine there was only one install to
    # have written it, so it counts as ours rather than being dropped from the budget.
    $peers = Get-AccountPeers
    if ($peers) {
        $ledger = @($ledger | Where-Object { -not $_.user -or $peers -contains $_.user })
    }
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
    #
    # The wall usually says when it comes down - "You've hit your session limit - resets 5:20pm" -
    # and using that beats guessing. A blind hour-long ladder against a three-hour limit means two
    # doomed attempts, each of which copies the whole tree before it can be told no, and then
    # waits up to an hour more after the quota is actually back. Read the time when it is there,
    # fall back to the ladder when it is not.
    $pause = if ($cfg.pause_minutes_after_limit) { [double]$cfg.pause_minutes_after_limit } else { 60 }
    $cutoff = (Get-Date).AddMinutes(-$pause)
    foreach ($row in $ledger) {
        if ($row.status -ne 'limit') { continue }
        $when = [datetime]::MinValue
        if (-not [datetime]::TryParse($row.when, [ref]$when)) { continue }
        $reset = Get-ResetTime $row.note $when
        if ($reset) {
            if ((Get-Date) -lt $reset) {
                return "usage limit hit at $($when.ToString('HH:mm')), resets at $($reset.ToString('HH:mm')) - standing down until then"
            }
            # The reset has passed, so this row is no longer a reason to wait. Not `break`:
            # a later row may carry a limit that has not.
            continue
        }
        if ($when -ge $cutoff) {
            return "a usage limit was hit at $($when.ToString('HH:mm')) - standing down for $pause min"
        }
    }
    return $null
}




# Run one prepared cell: pick the config, answer the prompt in a copy of base, record both.
function Invoke-Cell([string]$cellId, [string]$dir, [string]$model, [int]$files) {
    $prompt = Get-Content (Join-Path $dir 'prompt.txt') -Raw
    $now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $base = Join-Path $dir 'base'
    $work = Join-Path $dir 'work'
    if (Test-Path $work) { Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue }
    Copy-Item $base $work -Recurse -Force

    # The tree root travels in pick.json rather than in a script variable, because a deferred run
    # is drained by a later invocation that resolved a different one for its own prompt.
    $treeRoot = ''; $rootNote = ''
    $pickFile = Join-Path $dir 'pick.json'
    if (Test-Path $pickFile) {
        $pk = Get-Content $pickFile -Raw | ConvertFrom-Json
        $config = $pk.config; $rule = $pk.rule
        if ($pk.treeRoot) { $treeRoot = $pk.treeRoot }
        if ($pk.rootNote) { $rootNote = $pk.rootNote }
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
        elseif ($j.is_error) {
            # A usage limit does not arrive as junk on stderr. It arrives as a perfectly
            # well-formed result.json - is_error true, subtype "success", cost 0, one turn, and
            # the message inside `result` - so the parse succeeds and the stderr check below is
            # never reached. Recorded as 'error' it also never triggered the stand-down, which is
            # the whole point of noticing: the runner kept firing doomed runs, each copying the
            # whole tree first, until the quota came back hours later. Seen 2026-09-02:
            # api_error_status 429, "You've hit your session limit - resets 5:20pm".
            $msg = "$($j.result)".Trim()
            if ($j.api_error_status -eq 429 -or $msg -match 'usage limit|session limit|rate limit') {
                $status = 'limit'
                # The message carries the reset time; keeping it verbatim is what makes the row
                # readable later without going back to result.json.
                $note = if ($msg) { $msg } else { 'usage limit' }
            }
            else { $status = 'error'; $note = "agent reported is_error ($($j.subtype))" }
        }
        else { $status = 'ok' }
    }
    catch {
        $note = 'could not parse result.json'
        $blob = Get-Content $err -Raw -ErrorAction SilentlyContinue
        if ($blob -match 'usage limit|session limit') { $status = 'limit'; $note = 'usage limit' }
    }

    # A limit means this run has NOT happened yet, not that it is over. Everything a valid pair
    # needs still exists - the ancestor copy is untouched and Lea's own turn is recorded against
    # this same id - so the only missing piece is the shadow answer. Re-queue it and the next run
    # with budget drains it; the pair completes instead of being lost to a wall.
    #
    # Two things went with that. No patch is written: the work tree is an unmodified copy of
    # base, so the patch would be empty, and an empty patch is what makes prune() in
    # shadow-collect.js treat the run as finished and delete the very base the retry needs. And
    # deferred.json is no longer removed unconditionally - doing that dropped a DRAINED run out
    # of the queue the moment it hit a limit, losing it twice over.
    if ($status -eq 'limit') {
        $q = Join-Path $dir 'deferred.json'
        $at = (Get-Date).ToString('o')
        # Keep the original queue time so a re-queued run still ages out on its own schedule
        # rather than living forever by being retried.
        if (Test-Path $q) { try { $at = (Get-Content $q -Raw | ConvertFrom-Json).at } catch {} }
        @{ id = $cellId; model = $model; files = $files; at = $at; why = $note } |
            ConvertTo-Json | Set-Content $q -Encoding utf8
    }
    else {
        # git diff --no-index turns two directories into one reviewable patch, no repo needed.
        #
        # Written even when the diff is empty, and that is not a detail. A pipeline that yields
        # nothing leaves Set-Content creating no file at all, so a run whose agent changed no
        # files looked exactly like a run whose diff never happened - and prune() waits for this
        # file, so five runs from 30-31 August pinned their trees on disk indefinitely. An empty
        # shadow.patch is a real answer: the shadow arm touched nothing.
        $patch = (& git diff --no-index --binary -- $base $work 2>$null) -join "`n"
        Set-Content (Join-Path $dir 'shadow.patch') -Value $patch -Encoding utf8
        Remove-Item (Join-Path $dir 'deferred.json') -Force -ErrorAction SilentlyContinue
    }

    if ($rootNote) { $note = if ($note) { "$note; $rootNote" } else { $rootNote } }
    Write-Row @{ id = $cellId; when = $now; config = $config; model = $model; rule = $rule
                 status = $status; cost = $cost; turns = $turns; output = $outTok
                 duration = $secs; files = $files; note = $note; treeRoot = $treeRoot
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
#
# Session-start leads, and the order is the point: it is the reason nearly every prompt is
# dropped, so putting anything ahead of it files that prompt under a lesser reason and hides
# the real shape of the ledger. A prompt sent into an existing conversation means what the
# conversation made it mean; the shadow arm starts from nothing and answers a different
# question, at full price. Five such runs cost $5.74 here and produced no comparison at all.
if ($cfg.pair_session_start_only -and -not $SessionStart) {
    Update-RunModel
    Write-Row @{ id = $Id; when = $now; model = $runModel; status = 'skipped'
                 note = 'sent mid-conversation - the shadow arm has no conversation to resolve it against' }
    exit 0
}
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
# Decide the config before anything is copied, because the decision says whether a copy is
# needed at all: a prose question is answered in the reply, so neither arm touches the
# directory and the shadow can answer it anywhere - including from a home-directory session,
# which would otherwise contribute nothing.
$picked = & python (Join-Path $Shadow 'pick.py') $prompt 2>$null
$picks = "$picked".Trim() -split "`t", 3
$pickConfig = if ($picks[0]) { $picks[0] } else { 'bare' }
$pickRule = if ($picks.Count -gt 1) { $picks[1] } else { 'picker failed -> bare' }
$needsTree = -not ($picks.Count -gt 2 -and $picks[2] -eq 'notree')

$CwdFull = [IO.Path]::GetFullPath($Cwd).TrimEnd($Sep)
$TreeRoot = $CwdFull
$RootNote = ''
if ($needsTree) {
    $resolved = Resolve-TreeRoot $CwdFull
    if (-not $resolved.root) {
        Update-RunModel
        Write-Row @{ id = $Id; when = $now; config = $pickConfig; model = $runModel; rule = $pickRule
                     status = 'skipped'; treeRoot = ''
                     note = "no copyable tree: $($resolved.why). Add a directory to project_roots in config.json." }
        exit 0
    }
    $TreeRoot = $resolved.root
    if ($resolved.substituted) {
        $RootNote = "ran against project_roots entry $TreeRoot because $($resolved.why)"
        Write-Log "cwd not copyable -> $TreeRoot"
    }
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

    @{ config = $pickConfig; rule = $pickRule; needsTree = $needsTree
       treeRoot = $TreeRoot; rootNote = $RootNote } | ConvertTo-Json |
        Set-Content (Join-Path $RunDir 'pick.json') -Encoding utf8

    if ($needsTree) {
        $files = Copy-Tree $TreeRoot (Join-Path $RunDir 'base')
        if ($files -lt 0) {
            Update-RunModel
            Write-Row @{ id = $Id; when = $now; config = $pickConfig; model = $runModel
                         rule = $pickRule; status = 'skipped'; treeRoot = $TreeRoot
                         note = $script:CopyWhy }
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
