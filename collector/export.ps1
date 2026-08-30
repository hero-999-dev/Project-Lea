# Package what this machine has collected into one zip to send back.
#
# By default it packages the ledgers and the prompts you typed - what each arm cost, how many
# turns it took, and which prompt produced it. It does NOT package the diffs unless you ask,
# because those contain your code.
#
# Read the two ledgers before you send anything: shadow.csv and lea.csv are plain CSV, and
# prompts.jsonl is one line per prompt. Nothing else is included, and nothing is uploaded -
# this only writes a file.
#
# Usage:  pwsh -NoProfile -File export.ps1 [-IncludePatches] [-Since 2026-08-01] [-OutDir <path>]

param(
    # Include lea.patch and shadow.patch for each run. They are what makes a quality comparison
    # possible at all - and they are your source code. Off unless you say so.
    [switch]$IncludePatches,
    # Only runs on or after this date.
    [string]$Since = '',
    [string]$OutDir = ''
)

$ErrorActionPreference = 'Stop'
$shadow = $PSScriptRoot
if (-not (Test-Path (Join-Path $shadow 'config.json'))) {
    Write-Host "  x run this from the shadow directory (no config.json beside it)" -ForegroundColor Red
    exit 1
}
if (-not $OutDir) { $OutDir = [Environment]::GetFolderPath('Desktop') }

$tag = "{0}-{1}-{2}" -f $env:COMPUTERNAME, $env:USERNAME, (Get-Date -Format 'yyyyMMdd-HHmm')
$tag = ($tag -replace '[^A-Za-z0-9\-]', '_')
$stage = Join-Path ([IO.Path]::GetTempPath()) "lea-export-$tag"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage | Out-Null

$cut = [datetime]::MinValue
if ($Since) { $cut = [datetime]::Parse($Since) }

function Filter-Csv([string]$name) {
    $src = Join-Path $shadow $name
    if (-not (Test-Path $src)) { return 0 }
    $rows = @(Import-Csv $src)
    if ($Since) {
        $rows = @($rows | Where-Object {
            $w = [datetime]::MinValue
            [datetime]::TryParse($_.when, [ref]$w) -and $w -ge $cut
        })
    }
    if ($rows.Count) { $rows | Export-Csv (Join-Path $stage $name) -NoTypeInformation -Encoding utf8 }
    return $rows.Count
}

$shadowRows = Filter-Csv 'shadow.csv'
$leaRows = Filter-Csv 'lea.csv'

# One line per prompt, so a reader can see what produced each row without the run directories.
$promptFile = Join-Path $stage 'prompts.jsonl'
$prompts = 0
$patchDir = Join-Path $stage 'patches'
$patched = 0
foreach ($run in Get-ChildItem (Join-Path $shadow 'runs') -Directory -ErrorAction SilentlyContinue) {
    $p = Join-Path $run.FullName 'prompt.txt'
    if (-not (Test-Path $p)) { continue }
    if ($Since -and $run.CreationTime -lt $cut) { continue }
    @{ id = $run.Name; prompt = (Get-Content $p -Raw) } | ConvertTo-Json -Compress |
        Add-Content $promptFile -Encoding utf8
    $prompts++
    if ($IncludePatches) {
        foreach ($patch in 'lea.patch', 'shadow.patch') {
            $src = Join-Path $run.FullName $patch
            if (Test-Path $src) {
                New-Item -ItemType Directory -Force -Path $patchDir | Out-Null
                Copy-Item $src (Join-Path $patchDir "$($run.Name).$patch") -Force
                $patched++
            }
        }
    }
}

# The manifest says where the numbers came from, because a pooled dataset with unlabelled
# sources cannot be read: model, config and budgets all differ per machine.
$cfg = Get-Content (Join-Path $shadow 'config.json') -Raw | ConvertFrom-Json
@{
    machine       = $env:COMPUTERNAME
    user          = $env:USERNAME
    exported_at   = (Get-Date).ToString('o')
    since         = $Since
    shadow_rows   = $shadowRows
    lea_rows      = $leaRows
    prompts       = $prompts
    patches       = $patched
    includes_code = [bool]$IncludePatches
    model_setting = $cfg.model
    budgets       = @{ window = $cfg.window_budget_usd; per_model = $cfg.window_budget_by_model
                       daily = $cfg.daily_budget_usd; per_run = $cfg.budget_usd_per_run }
} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $stage 'manifest.json') -Encoding utf8

$zip = Join-Path $OutDir "lea-shadow-$tag.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip
Remove-Item $stage -Recurse -Force

Write-Host ''
Write-Host "  wrote $zip" -ForegroundColor Green
Write-Host "  $shadowRows shadow row(s), $leaRows Lea row(s), $prompts prompt(s), $patched patch file(s)"
if (-not $IncludePatches) {
    Write-Host '  no code included. Add -IncludePatches to send the diffs too - they are what makes' -ForegroundColor Yellow
    Write-Host '  a quality comparison possible, and they are your source code. Your call.' -ForegroundColor Yellow
}
Write-Host ''
