# Fetch the latest report pages from the private repo and open them in a browser.
#
# There is a published URL as well - https://hero-999-dev.github.io/Project-Lea/, behind a
# password gate - but this stays because a local copy needs no network, no password and no
# secure context, and because GitHub's own file view renders HTML as source rather than as a
# page. This clones on first use and pulls afterwards, so it is safe to run repeatedly.
#
# Works on any machine that has `gh` and is signed in as the account that owns the repo:
#     gh auth login          # once per machine
#     pwsh -File ac.ps1      # or: pwsh -File ac.ps1 -Into D:\somewhere
#
# It clones on first use and pulls afterwards, so it is safe to run repeatedly.

param(
    # Where to keep the working copy. Defaults to a stable per-user location so a second run
    # pulls rather than cloning again.
    [string]$Into = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Project-Lea'),
    [string]$Repo = 'hero-999-dev/Project-Lea',
    # Which page to open. The index frames all the others.
    [string]$Page = 'index.html',
    # Fetch only; do not open a browser.
    [switch]$NoOpen
)

$ErrorActionPreference = 'Stop'
function Say([string]$m, [string]$c = 'Gray') { Write-Host $m -ForegroundColor $c }

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Say "  x the GitHub CLI (gh) is not on PATH. Install it, then run: gh auth login" Red
    exit 1
}
# Checked rather than assumed: a clone of a private repo fails with a confusing git error when
# the CLI is installed but not signed in.
& gh auth status *>$null
if ($LASTEXITCODE -ne 0) {
    Say "  x gh is installed but not signed in. Run: gh auth login" Red
    exit 1
}

if (Test-Path (Join-Path $Into '.git')) {
    Say "  pulling into $Into"
    & git -C $Into -c credential.helper='!gh auth git-credential' pull --ff-only *>$null
    if ($LASTEXITCODE -ne 0) { Say "  ! pull failed - opening whatever is already there" Yellow }
}
else {
    if (Test-Path $Into) {
        Say "  x $Into exists and is not a clone. Pass -Into <somewhere else>." Red
        exit 1
    }
    Say "  cloning $Repo into $Into"
    & gh repo clone $Repo $Into -- --depth 1 *>$null
    if ($LASTEXITCODE -ne 0) { Say "  x clone failed. Are you signed in as an account with access?" Red; exit 1 }
}

$target = Join-Path $Into "site\$Page"
if (-not (Test-Path $target)) {
    Say "  x no such page: $target" Red
    Say "    available:" Gray
    Get-ChildItem (Join-Path $Into 'site') -Filter *.html | ForEach-Object { Say "      $($_.Name)" }
    exit 1
}

$stamp = (& git -C $Into log -1 --format='%h %ad %s' --date=short) 2>$null
Say "  $stamp"
Say "  $target" Green
if (-not $NoOpen) { Start-Process $target }
