# sync-dev.ps1 — 拉取上游更新,以本地文件修改的形式应用到 dev 分支
# 用法: .\scripts\sync-dev.ps1
#
# 效果: 上游改动会变成工作区中未提交的文件修改,
#       可用 IDEA 逐文件对比、审查、处理后自行提交。

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

# ── 状态变量 ──────────────────────────────────────────

$applied       = $false
$hasConflicts  = $false
$upstreamNew   = 0
$changedFiles  = @()
$conflictFiles = @()

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
    $upstreamNew = [int](git rev-list "$currentBranch..upstream/main" --count 2>&1)
    $devOwn      = [int](git rev-list "upstream/main..$currentBranch" --count 2>&1)

    if ($upstreamNew -eq 0) {
        Write-Ok "dev 已包含所有上游更新,无需同步"
        return   # finally 仍会执行(恢复 stash)
    }

    Write-Info "上游新增 $upstreamNew 个提交,你的独立提交 $devOwn 个"

    # 3. 找共同祖先,生成上游补丁
    $mergeBase = git merge-base $currentBranch upstream/main
    if ($LASTEXITCODE -ne 0) {
        Write-Err "无法计算 merge-base"
        exit 1
    }

    Write-Info "正在生成上游变更补丁..."
    git diff "$mergeBase..upstream/main" > "$env:TEMP\sync-dev-upstream.patch"
    if ($LASTEXITCODE -ne 0) {
        Write-Err "生成 diff 失败"
        exit 1
    }

    $patchSize = (Get-Item "$env:TEMP\sync-dev-upstream.patch").Length
    if ($patchSize -eq 0) {
        Write-Ok "补丁为空,无实际变更"
        Remove-Item "$env:TEMP\sync-dev-upstream.patch" -ErrorAction SilentlyContinue
        return
    }

    # 4. 预检: 能否干净应用?
    Write-Info "正在应用上游改动到工作区..."
    Invoke-GitQuiet @("apply", "--check", "$env:TEMP\sync-dev-upstream.patch")
    $canApplyClean = ($LASTEXITCODE -eq 0)

    # 5. 应用补丁
    if ($canApplyClean) {
        # 干净应用 — 直接 apply
        git apply "$env:TEMP\sync-dev-upstream.patch" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Err "应用补丁失败"
            exit 1
        }
        $applied = $true
        Write-Ok "上游改动已干净应用到工作区"
    } else {
        # 有冲突区域 — 使用三路合并,在冲突处插入标记
        git apply --3way "$env:TEMP\sync-dev-upstream.patch" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Err "应用补丁失败,请检查文件状态后重试"
            exit 1
        }
        $applied = $true

        # 检查是否有冲突标记
        Invoke-GitQuiet @("diff", "--check")
        if ($LASTEXITCODE -ne 0) {
            $hasConflicts = $true
            $conflictFiles = @(git diff --name-only --diff-filter=U 2>&1)
            Write-Warn "部分文件存在冲突区域,已插入合并标记"
        } else {
            Write-Ok "上游改动已应用到工作区"
        }
    }

    # 获取变更文件列表
    $changedFiles = @(git diff --name-only 2>&1)

    # 清理补丁文件
    Remove-Item "$env:TEMP\sync-dev-upstream.patch" -ErrorAction SilentlyContinue

} finally {
    # ── 恢复现场 ──────────────────────────────────────

    if ($stashed) {
        Write-Info "恢复 stash 暂存..."
        git stash pop
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "stash pop 失败,请手动执行: git stash pop"
        }
    }

    # ── 结果面板 ──────────────────────────────────────

    Write-Host ""

    $color = if ($hasConflicts) { "Yellow" } else { "Green" }
    Write-Host "  ╔══════════════════════════════════════════════╗" -ForegroundColor $color
    Write-Host "  ║  同步结果                                     ║" -ForegroundColor $color
    Write-Host "  ╠══════════════════════════════════════════════╣" -ForegroundColor $color

    if (-not $applied) {
        if ($upstreamNew -eq 0) {
            Write-Host "  ║  无需同步,已是最新                           ║" -ForegroundColor Green
        } else {
            Write-Host "  ║  同步未完成                                   ║" -ForegroundColor Red
        }
    } else {
        Write-Host "  ║  已应用 $($changedFiles.Count) 个文件的变更" -ForegroundColor Green

        if ($hasConflicts) {
            Write-Host "  ║                                              ║" -ForegroundColor $color
            Write-Host "  ║  ⚠ 以下文件存在冲突区域:                     ║" -ForegroundColor Yellow
            foreach ($f in $conflictFiles) {
                $display = if ($f.Length -gt 38) { "..." + $f.Substring($f.Length - 35) } else { $f }
                Write-Host "  ║    $display" -ForegroundColor Yellow
            }
            if ($conflictFiles.Count -gt 5) {
                $extra = $conflictFiles.Count - 5
                Write-Host "  ║    ...及其他 $extra 个文件" -ForegroundColor Yellow
            }
        }
    }

    Write-Host "  ╠══════════════════════════════════════════════╣" -ForegroundColor $color

    if ($applied) {
        Write-Host "  ║  下一步:                                     ║" -ForegroundColor Cyan
        Write-Host "  ║  1. 用 IDEA 查看文件改动,审查上游变更       ║" -ForegroundColor White
        if ($hasConflicts) {
            Write-Host "  ║  2. 搜索 <<<<<<< 定位冲突,手动解决           ║" -ForegroundColor White
            Write-Host "  ║  3. git add . && git commit                  ║" -ForegroundColor White
        } else {
            Write-Host "  ║  2. 满意后 git add . && git commit           ║" -ForegroundColor White
        }
        Write-Host "  ║                                              ║" -ForegroundColor $color
        Write-Host "  ║  不接受改动:                                 ║" -ForegroundColor Cyan
        Write-Host "  ║    git checkout .  (丢弃所有本地修改)        ║" -ForegroundColor White
    }

    Write-Host "  ╚══════════════════════════════════════════════╝" -ForegroundColor $color
    Write-Host ""
}
