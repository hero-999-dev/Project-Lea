# Helpers shared by run-shadow.ps1 and its tests.
#
# They live here so a test can dot-source them. The tests used to lift these out of
# run-shadow.ps1 by AST and Invoke-Expression the text, which is a textbook script-malware shape
# - build code from text, then run it - and this machine's antivirus blocked it on 2026-09-02.
# It was right to. A file both sides dot-source removes the pattern instead of working around
# the detection.
#
# $cfg, $Sep and $script:CopyWhy come from the caller's scope, which is what dot-sourcing gives.

# Which Anthropic account this install signs in with, per config.json's `accounts` map. Labels are
# names the user chooses, never credentials; only equality matters. $null means the machine has no
# map, which is the single-install case and the behaviour from before the key existed. An install
# absent from a map that exists is treated as its own account.
function Get-AccountLabel {
    if (-not $cfg.accounts) { return $null }
    $l = $cfg.accounts."$env:USERNAME"
    if ($l) { return "$l" }
    return "$env:USERNAME"
}

function Get-Family([string]$m) {
    switch -Regex ($m) { 'opus' { 'opus' } 'haiku' { 'haiku' } default { 'sonnet' } }
}

# Returns the reason this run cannot go ahead right now, or $null if it can. Budget reasons are
# temporary - the caller defers on those; a usage limit is one too.
# Which installs share this one's Anthropic account, by the labels in config.json. Returns $null
# when there is no map, which means "count every row" - the behaviour before the key existed and
# the right one for a machine with a single install.
#
# `return ,@(...)`: PowerShell unwraps a one-element array on return, and a bare string would
# make `-contains` below compare characters.
function Get-AccountPeers {
    $mine = Get-AccountLabel
    if (-not $mine) { return $null }
    if ($mine -eq "$env:USERNAME" -and -not $cfg.accounts."$env:USERNAME") {
        return , @("$env:USERNAME")         # in no map's list: its own account
    }
    return , @($cfg.accounts.PSObject.Properties |
               Where-Object { $_.Value -eq $mine } | ForEach-Object { $_.Name })
}

# "You've hit your session limit - resets 5:20pm (Europe/Warsaw)" -> the next 5:20pm.
#
# The timezone in the message is the machine's own, so it is read rather than converted. A time
# that has already passed today belongs to tomorrow. Anything unparseable returns $null and the
# caller keeps its ladder - a wrong reset time would be worse than no reset time, because it
# would release the stand-down early and spend a copy proving the wall is still there.
function Get-ResetTime([string]$note, [datetime]$hitAt) {
    if (-not $note) { return $null }
    if ($note -notmatch 'resets?\s+(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*([ap])\.?m\.?') { return $null }
    $h = [int]$Matches[1]
    $m = if ($Matches[2]) { [int]$Matches[2] } else { 0 }
    if ($h -lt 1 -or $h -gt 12 -or $m -gt 59) { return $null }
    if ($Matches[3] -eq 'p' -and $h -ne 12) { $h += 12 }
    if ($Matches[3] -eq 'a' -and $h -eq 12) { $h = 0 }
    $reset = $hitAt.Date.AddHours($h).AddMinutes($m)
    if ($reset -le $hitAt) { $reset = $reset.AddDays(1) }
    return $reset
}

# Copy $from into $to, honouring the caps. Returns the file count, or -1 with $script:CopyWhy set.
# -ProbeOnly walks the tree and counts, copying nothing: it answers "would this fit?" before a
# byte is written. It is the SAME function on purpose - a probe that agreed with the copy only
# most of the time would be worse than no probe, because the disagreement would show up as a
# half-copied tree thrown away after the fact.
function Copy-Tree([string]$from, [string]$to, [switch]$ProbeOnly) {
    if (-not $ProbeOnly) { New-Item -ItemType Directory -Force -Path $to | Out-Null }
    $excludeDirs = @($cfg.copy.exclude_dirs)
    $maxFileBytes = $cfg.copy.max_file_mb * 1MB
    $scanCap = if ($ProbeOnly) {
        if ($cfg.copy.max_probe_seconds) { [int]$cfg.copy.max_probe_seconds } else { 20 }
    } elseif ($cfg.copy.max_scan_seconds) { [int]$cfg.copy.max_scan_seconds } else { 60 }
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
            if (-not $ProbeOnly) {
                $dest = Join-Path $to $rel
                New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent) | Out-Null
                Copy-Item -LiteralPath $full -Destination $dest -Force -ErrorAction SilentlyContinue
            }
        }
    }
    catch { $script:CopyWhy = "could not read the tree: $($_.Exception.Message)" }
    if ($script:CopyWhy) {
        if (-not $ProbeOnly) { Remove-Item $to -Recurse -Force -ErrorAction SilentlyContinue }
        return -1
    }
    return $count
}

# Which directory the shadow arm copies.
#
# Normally the session's own working directory: that IS the experiment, and both arms starting
# from one tree is what makes the two patches comparable. But the directory a terminal happens to
# be open in is not always a statement about the task, and throwing the prompt away because of
# where the window was open costs the one measurable prompt that session had.
#
# What actually fits is not obvious from a directory's size, because the copier skips any file
# over max_file_mb before it counts. Probed with these caps (15,000 files / 600 MB / 25 MB per
# file): the project 885 files / 56 MB, its parent `AI Workspace` 1,649 / 399 MB after skipping
# 23 files worth 1,962 MB - both fit. One home directory reached the 600 MB cap at 1,473 files,
# and another did not finish inside the 20 s probe. So a parent directory is usually fine
# and a home directory usually is not, but neither is assumed: the probe decides, every time.
#
# So: if the cwd cannot be copied, fall back to the first `project_roots` entry that can, and say
# so. The substitution is never silent - the row records which root ran, and `report.py` compares
# it against Lea's own cwd, so a pair whose arms started from different trees is reported apart
# from one whose arms did not. That distinction is the whole reason the column exists.
function Resolve-TreeRoot([string]$cwd) {
    # Named homeDir, not home: PowerShell variable names are case-insensitive, so $home would BE
    # $HOME and this function would quietly redefine the profile path for everything after it.
    $homeDir = [IO.Path]::GetFullPath($HOME).TrimEnd($Sep)
    $why = ''
    if ($cwd -eq $homeDir -or $homeDir.StartsWith($cwd + $Sep)) {
        # Not probed: it is known not to fit, and probing it is what costs the 120 seconds.
        $why = "the working directory is a home directory ($cwd)"
    }
    else {
        if ((Copy-Tree $cwd '' -ProbeOnly) -ge 0) {
            return @{ root = $cwd; substituted = $false; why = '' }
        }
        $why = "the working directory could not be copied ($cwd): $script:CopyWhy"
    }
    foreach ($cand in @($cfg.project_roots)) {
        if (-not $cand) { continue }
        $full = ''
        try { $full = [IO.Path]::GetFullPath($cand).TrimEnd($Sep) } catch { continue }
        if (-not (Test-Path -LiteralPath $full)) { continue }
        if ((Copy-Tree $full '' -ProbeOnly) -ge 0) {
            return @{ root = $full; substituted = $true; why = $why }
        }
    }
    return @{ root = ''; substituted = $false; why = $why }
}

