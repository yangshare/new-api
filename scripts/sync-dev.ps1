# sync-dev.ps1 - fetch upstream changes on dev and print a manual review command.
# Usage: .\scripts\sync-dev.ps1

$ErrorActionPreference = "Stop"

function Write-Info($msg) { Write-Host "  $msg" -ForegroundColor Cyan }
function Write-Ok($msg) { Write-Host "  $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  $msg" -ForegroundColor Yellow }
function Write-Err($msg) { Write-Host "  $msg" -ForegroundColor Red }

function Invoke-GitQuiet($gitArgs) {
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & git @gitArgs *> $null
        return $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
}

$upstreamUrl = git remote get-url upstream 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Err "upstream remote was not found"
    Write-Info "Add it first: git remote add upstream <upstream-url>"
    exit 1
}

$currentBranch = git branch --show-current
if ($currentBranch -ne "dev") {
    Write-Warn "current branch is $currentBranch, not dev"
    $answer = Read-Host "  Switch to dev? (Y/n)"
    if ($answer -eq "" -or $answer -match "^[Yy]") {
        git checkout dev
        if ($LASTEXITCODE -ne 0) {
            Write-Err "failed to switch to dev"
            exit 1
        }
        $currentBranch = "dev"
    } else {
        Write-Warn "cancelled dev sync; still on $currentBranch"
        exit 1
    }
}

Write-Info "fetching latest code from upstream..."
$fetchExitCode = Invoke-GitQuiet @("fetch", "upstream")
if ($fetchExitCode -ne 0) {
    Write-Err "fetch upstream failed; check your network or remote config"
    exit 1
}
Write-Ok "fetch complete"

$upstreamNew = [int](git rev-list "$currentBranch..upstream/main" --count 2>&1)
$devOwn = [int](git rev-list "upstream/main..$currentBranch" --count 2>&1)

Write-Host ""
Write-Host "  ==============================================" -ForegroundColor Cyan
Write-Host "  Upstream sync info" -ForegroundColor Cyan
Write-Host "  ----------------------------------------------" -ForegroundColor Cyan
Write-Host "  Current branch: $currentBranch" -ForegroundColor Cyan
Write-Host "  Upstream-only commits: $upstreamNew" -ForegroundColor Cyan
Write-Host "  Dev-only commits: $devOwn" -ForegroundColor Cyan
Write-Host "  ----------------------------------------------" -ForegroundColor Cyan

if ($upstreamNew -eq 0) {
    Write-Host "  No merge needed; dev already includes upstream/main." -ForegroundColor Green
} else {
    Write-Host "  Suggested manual review merge:" -ForegroundColor Cyan
    Write-Host "    git merge --no-commit --no-ff upstream/main" -ForegroundColor White
    Write-Host ""
    Write-Host "  Inspect the merge result before committing:" -ForegroundColor Cyan
    Write-Host "    git status" -ForegroundColor White
    Write-Host "    git diff --cached" -ForegroundColor White
    Write-Host "    git diff" -ForegroundColor White
    Write-Host ""
    Write-Host "  If there are conflicts: resolve them, git add, then git commit." -ForegroundColor Cyan
    Write-Host "  To reject the result: git merge --abort" -ForegroundColor Cyan
}

Write-Host "  ==============================================" -ForegroundColor Cyan
Write-Host ""
