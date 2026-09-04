# Claude Code statusline: current directory, model, and the Project Lea badge.
#
# Until 2026-08-30 this also invoked caveman's and ponytail's own badge scripts out of the
# plugin cache. Those plugins were disabled on 08-26 and uninstalled on 08-30, so the calls
# went with them; the configuration is now one hook and nothing else.
#
# The Lea badge is drawn only when the hook that defines Lea is actually on disk, so it can
# never claim a configuration that is not loaded.
#
# Everything writes through [Console]::Write rather than the PowerShell pipeline: Claude Code
# reads this script's raw stdout, and pipeline output would arrive with its own formatting.

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Esc = [char]27
$Sep = $false

function Write-Segment($Text, $Color) {
    if ($script:Sep) { [Console]::Write(' ') }
    [Console]::Write("${script:Esc}[38;5;${Color}m${Text}${script:Esc}[0m")
    $script:Sep = $true
}

# Claude Code pipes the session state in as JSON on stdin. Absent when the script is run by
# hand, so every field below is treated as optional.
$Status = $null
try { $Status = [Console]::In.ReadToEnd() | ConvertFrom-Json } catch {}

$Dir = $Status.workspace.current_dir
if (-not $Dir) { $Dir = $PWD.Path }
if ($Dir) { Write-Segment (Split-Path -Leaf $Dir) 109 }

$Model = $Status.model.display_name
if ($Model) { Write-Segment $Model 245 }

# Which arm this session is running as, read from settings.json rather than from the presence of
# lea.js on disk. The file stays put when the arm is switched - `shadow/arm.py` parks the hook
# ENTRY, so a check for the file would have gone on saying "Project Lea" through a whole stock
# session and the badge would have contradicted what the ledger recorded.
#
# Same rule as liveConfig() in shadow-collect.js: a SessionStart hook pointing at lea.js, and no
# plugins. 117 is the light blue of the xterm-256 palette; it reads on dark and light terminals.
$Arm = $null
try {
    $S = Get-Content -LiteralPath (Join-Path $HOME '.claude\settings.json') -Raw | ConvertFrom-Json
    $Plugins = @($S.enabledPlugins.PSObject.Properties | Where-Object { $_.Value }).Count
    $HasLea = ($S.hooks.SessionStart | ConvertTo-Json -Depth 10 -Compress) -match 'lea\.js'
    if ($HasLea -and $Plugins -eq 0) { $Arm = @('Project Lea', 117) }
    elseif ($HasLea) { $Arm = @("Project Lea +$Plugins plugins", 179) }
    else { $Arm = @('stock arm', 208) }
} catch {}
if ($Arm) { Write-Segment $Arm[0] $Arm[1] }

# What the shadow arm will do with this session, said here rather than left as a rule to remember.
# It answers each prompt a second time inside a COPY of the working directory, so the directory
# has to be copyable. Whether it is cannot be decided here - the real test is a 2-3 second walk
# and this runs on every render - so only the cheap case is checked: a home directory, which the
# runner refuses outright. Everything else is left to the runner's own probe, which is the copy
# routine itself.
if (Test-Path -LiteralPath (Join-Path $HOME '.claude\hooks\shadow-enqueue.js')) {
    $InHome = $false
    try {
        $HomeFull = [IO.Path]::GetFullPath($HOME).TrimEnd([IO.Path]::DirectorySeparatorChar)
        $DirFull = [IO.Path]::GetFullPath($Dir).TrimEnd([IO.Path]::DirectorySeparatorChar)
        $InHome = ($DirFull -eq $HomeFull -or
                   $HomeFull.StartsWith($DirFull + [IO.Path]::DirectorySeparatorChar))
    } catch {}
    if (-not $InHome) { Write-Segment 'shadow' 114 }
    else {
        # A home directory is not the end of it any more: with project_roots configured the runner
        # falls back to one of those and records that the two arms started from different trees.
        $HasRoots = $false
        try {
            $ShadowDir = (Get-Content -LiteralPath (Join-Path $HOME '.claude\shadow-dir.txt') -Raw).Trim()
            $ShadowCfg = Get-Content -LiteralPath (Join-Path $ShadowDir 'config.json') -Raw | ConvertFrom-Json
            $HasRoots = @($ShadowCfg.project_roots).Where({ $_ }).Count -gt 0
        } catch {}
        if ($HasRoots) { Write-Segment 'shadow: project root' 179 }
        else { Write-Segment 'shadow: prose only' 244 }
    }
}

# The count the whole shadow arm is working towards: pairs where both arms answered the same
# prompt AND did comparable work. It gates the savings headline - below the target the headline
# stays a projection - so it belongs where it is seen without being asked for.
#
# Read from a cached file, never computed here. Working it out means joining both ledgers and
# reading every run's artifacts, about 0.6 s, and this script runs on every render; the Stop hook
# refreshes the file once per turn instead. No file, no segment - a badge that guesses is worse
# than no badge.
try {
    $ShadowDir = (Get-Content -LiteralPath (Join-Path $HOME '.claude\shadow-dir.txt') -Raw).Trim()
    if (-not $ShadowDir) { $ShadowDir = Join-Path $HOME '.claude\shadow' }
    $CounterFile = Join-Path $ShadowDir 'counter.json'
    if (Test-Path -LiteralPath $CounterFile) {
        $C = Get-Content -LiteralPath $CounterFile -Raw | ConvertFrom-Json
        $Need = if ($C.needed) { [int]$C.needed } else { 20 }
        $Have = [int]$C.usable
        # Red at zero, amber while collecting, green at the target - the same three states the
        # SVG badge uses, so the two cannot say different things at a glance.
        $Colour = if ($Have -ge $Need) { 114 } elseif ($Have -gt 0) { 179 } else { 203 }
        Write-Segment "pairs $Have/$Need" $Colour

        # The wide comparison, which is the one a stock session actually fills. Without it a
        # stock session shows no progress anywhere - the pair counter cannot move from one - and
        # looks like nothing is being collected, which is what put the second arm here.
        # Grey until both sides exist, because one side alone compares with nothing.
        $Lea = [int]$C.lea_rows
        $Stok = [int]$C.stok_rows
        if ($Lea -gt 0 -or $Stok -gt 0) {
            $Both = if ($Lea -gt 0 -and $Stok -gt 0) { 114 } else { 244 }
            Write-Segment "lea $Lea / stock $Stok" $Both
        }
    }
} catch {}
