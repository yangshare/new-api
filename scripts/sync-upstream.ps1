# sync-upstream.ps1 — 同步上游仓库更新到 main 分支并推送到 fork
# 用法: .\scripts\sync-upstream.ps1

$ErrorActionPreference = "Stop"

function Write-Info($msg) { Write-Host "  $msg" -ForegroundColor Cyan }
function Write-Ok($msg) { Write-Host "  $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  $msg" -ForegroundColor Yellow }
function Write-Err($msg) { Write-Host "  $msg" -ForegroundColor Red }

# ── 前置检查 ──────────────────────────────────────────

# 检查 upstream remote 是否存在
$upstreamUrl = git remote get-url upstream 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Err "未找到 upstream remote"
    Write-Info "请先添加: git remote add upstream <上游仓库URL>"
    exit 1
}

# ── 保存现场 ──────────────────────────────────────────

$originalBranch = git branch --show-current
$stashed = $false

# 检查是否有未提交的改动
$status = git status --porcelain
if ($status) {
    Write-Info "检测到未提交的改动,正在 stash 暂存..."
    git stash push -m "sync-upstream-auto-stash" --include-untracked
    if ($LASTEXITCODE -ne 0) {
        Write-Err "stash 失败,请手动处理后重试"
        exit 1
    }
    $stashed = $true
    Write-Ok "已暂存"
}

# ── 主流程（try/finally 保证恢复现场） ─────────────────

$syncedCount = 0
$failed = $false

try {
    # 1. 切换到 main
    Write-Info "切换到 main 分支..."
    git checkout main 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Err "切换到 main 分支失败"
        $failed = $true; return
    }

    # 2. 拉取上游
    Write-Info "从 upstream 拉取最新代码..."
    git fetch upstream 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Err "fetch upstream 失败,请检查网络连接"
        $failed = $true; return
    }

    # 3. 计算同步前的提交差
    $beforeCount = (git rev-list main..upstream/main --count 2>&1)
    if ($beforeCount -eq 0) {
        Write-Ok "main 已经是最新,无需同步"
        return
    }

    # 4. 快进合并
    Write-Info "快进合并 upstream/main（$beforeCount 个新提交）..."
    $mergeOutput = git merge --ff-only upstream/main 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Err "快进合并失败！main 分支可能包含非上游的提交"
        Write-Info "错误详情: $mergeOutput"
        Write-Info "建议: 先手动清理 main 分支上的非上游提交，然后重试"
        $failed = $true; return
    }
    $syncedCount = $beforeCount

    # 5. 推送到 fork
    Write-Info "推送到 origin/main..."
    git push origin main 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "推送到 origin 失败,但本地 main 已更新"
        Write-Info "你可以稍后手动执行: git push origin main"
    }

} finally {
    # ── 恢复现场 ──────────────────────────────────────

    if ($originalBranch -and $originalBranch -ne "main") {
        Write-Info "切回 $originalBranch 分支..."
        git checkout $originalBranch 2>&1 | Out-Null
    }

    if ($stashed) {
        Write-Info "恢复 stash 暂存..."
        git stash pop 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "stash pop 失败,请手动执行: git stash pop"
        }
    }

    # ── 结果摘要 ──────────────────────────────────────

    Write-Host ""
    if ($failed) {
        Write-Err "同步未完成,请根据上方提示处理"
    } elseif ($syncedCount -gt 0) {
        Write-Host "  ╔══════════════════════════════════════╗" -ForegroundColor Green
        Write-Host "  ║  同步完成                             ║" -ForegroundColor Green
        Write-Host "  ╠══════════════════════════════════════╣" -ForegroundColor Green
        Write-Host "  ║  新同步提交: $syncedCount 个" -ForegroundColor Green
        Write-Host "  ║  main 已与 upstream/main 一致        ║" -ForegroundColor Green
        Write-Host "  ╚══════════════════════════════════════╝" -ForegroundColor Green
    }
}
