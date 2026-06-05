# sync-dev.ps1 — 在 dev 分支拉取上游更新,展示信息面板,合并由用户手动执行
# 用法: .\scripts\sync-dev.ps1

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

# ── 前置检查 ──────────────────────────────────────────

# 检查 upstream remote 是否存在
$upstreamUrl = git remote get-url upstream 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Err "未找到 upstream remote"
    Write-Info "请先添加: git remote add upstream <上游仓库URL>"
    exit 1
}

# 检查当前分支
$currentBranch = git branch --show-current
if ($currentBranch -ne "dev") {
    Write-Warn "当前分支是 $currentBranch,不是 dev"
    $answer = Read-Host "  是否切换到 dev 分支?(Y/n)"
    if ($answer -eq "" -or $answer -match "^[Yy]") {
        git checkout dev
        if ($LASTEXITCODE -ne 0) {
            Write-Err "切换到 dev 分支失败"
            exit 1
        }
        $currentBranch = "dev"
    } else {
        Write-Warn "已取消 dev 分支同步,当前仍在 $currentBranch 分支"
        exit 1
    }
}

# ── 保存现场 ──────────────────────────────────────────

$stashed = $false

$status = git status --porcelain
if ($status) {
    Write-Info "检测到未提交的改动,正在 stash 暂存..."
    git stash push -m "sync-dev-auto-stash" --include-untracked
    if ($LASTEXITCODE -ne 0) {
        Write-Err "stash 失败,请手动处理后重试"
        exit 1
    }
    $stashed = $true
    Write-Ok "已暂存"
}

# ── 主流程 ────────────────────────────────────────────

try {
    # 1. 拉取上游
    Write-Info "从 upstream 拉取最新代码..."
    $fetchExitCode = Invoke-GitQuiet @("fetch", "upstream")
    if ($fetchExitCode -ne 0) {
        Write-Err "fetch upstream 失败,请检查网络连接"
        exit 1
    }
    Write-Ok "拉取完成"

    # 2. 计算提交差
    $upstreamNew = (git rev-list "$currentBranch..upstream/main" --count 2>&1)
    $devOwn = (git rev-list "upstream/main..$currentBranch" --count 2>&1)

    # 3. 打印信息面板
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║  上游同步信息                             ║" -ForegroundColor Cyan
    Write-Host "  ╠══════════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "  ║  当前分支: $currentBranch" -ForegroundColor Cyan

    if ($upstreamNew -eq 0) {
        Write-Host "  ║  上游新增提交: 0 个(已是最新)          ║" -ForegroundColor Green
    } else {
        Write-Host "  ║  上游新增提交: $upstreamNew 个" -ForegroundColor Yellow
    }

    Write-Host "  ║  你的独立提交: $devOwn 个" -ForegroundColor Cyan
    Write-Host "  ╠══════════════════════════════════════════╣" -ForegroundColor Cyan

    if ($upstreamNew -eq 0) {
        Write-Host "  ║  无需合并,dev 已包含所有上游更新        ║" -ForegroundColor Green
    } else {
        Write-Host "  ║  建议手动执行可审查合并:                 ║" -ForegroundColor Cyan
        Write-Host "  ║    git merge --no-commit --no-ff upstream/main" -ForegroundColor White
        Write-Host "  ║                                          ║" -ForegroundColor Cyan
        Write-Host "  ║  合并后先检查自动合并结果:               ║" -ForegroundColor Cyan
        Write-Host "  ║    git status                            ║" -ForegroundColor White
        Write-Host "  ║    git diff --cached                     ║" -ForegroundColor White
        Write-Host "  ║    git diff                              ║" -ForegroundColor White
        Write-Host "  ║                                          ║" -ForegroundColor Cyan
        Write-Host "  ║  如有冲突: 解决后 git add,再 git commit  ║" -ForegroundColor Cyan
        Write-Host "  ║  不接受结果: git merge --abort           ║" -ForegroundColor Cyan
    }

    Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

} finally {
    # ── 恢复现场 ──────────────────────────────────────

    if ($stashed) {
        Write-Info "恢复 stash 暂存..."
        git stash pop
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "stash pop 失败,请手动执行: git stash pop"
        }
    }
}
