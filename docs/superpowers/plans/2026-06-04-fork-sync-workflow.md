# Fork 上游同步工作流 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 实现两个 PowerShell 脚本，用于优雅地同步 fork 项目的上游更新。

**架构：** 两个独立脚本各司其职——`sync-upstream.ps1` 负责将上游代码快进到 main 并推送到 fork；`sync-dev.ps1` 负责在 dev 分支拉取上游更新并展示信息面板，合并由用户手动执行。两个脚本共享 stash/pop 保护和现场恢复机制。

**技术栈：** PowerShell 7+、Git CLI

---

## 文件结构

| 文件 | 操作 | 职责 |
|---|---|---|
| `scripts/sync-upstream.ps1` | 创建 | 同步上游 → main → origin/main |
| `scripts/sync-dev.ps1` | 创建 | 为 dev 拉取上游更新 + 信息面板 |

---

### 任务 1：创建 sync-upstream.ps1

**文件：**
- 创建：`scripts/sync-upstream.ps1`

- [ ] **步骤 1：创建脚本文件并编写完整代码**

```powershell
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
    Write-Info "检测到未提交的改动，正在 stash 暂存..."
    git stash push -m "sync-upstream-auto-stash" --include-untracked
    if ($LASTEXITCODE -ne 0) {
        Write-Err "stash 失败，请手动处理后重试"
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
        Write-Err "fetch upstream 失败，请检查网络连接"
        $failed = $true; return
    }

    # 3. 计算同步前的提交差
    $beforeCount = (git rev-list main..upstream/main --count 2>&1)
    if ($beforeCount -eq 0) {
        Write-Ok "main 已经是最新，无需同步"
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
        Write-Warn "推送到 origin 失败，但本地 main 已更新"
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
            Write-Warn "stash pop 失败，请手动执行: git stash pop"
        }
    }

    # ── 结果摘要 ──────────────────────────────────────

    Write-Host ""
    if ($failed) {
        Write-Err "同步未完成，请根据上方提示处理"
    } elseif ($syncedCount -gt 0) {
        Write-Host "  ╔══════════════════════════════════════╗" -ForegroundColor Green
        Write-Host "  ║  同步完成                             ║" -ForegroundColor Green
        Write-Host "  ╠══════════════════════════════════════╣" -ForegroundColor Green
        Write-Host "  ║  新同步提交: $syncedCount 个" -ForegroundColor Green
        Write-Host "  ║  main 已与 upstream/main 一致        ║" -ForegroundColor Green
        Write-Host "  ╚══════════════════════════════════════╝" -ForegroundColor Green
    }
}
```

- [ ] **步骤 2：手动运行脚本验证基本流程**

运行（确保当前在 main 分支或 dev 分支上）：
```powershell
.\scripts\sync-upstream.ps1
```

预期：
- 如果有 upstream 更新，会看到同步完成的摘要，显示新同步的提交数
- 如果已经是最新，会看到 "main 已经是最新，无需同步"
- 脚本结束时回到原来的分支
- 如果有未提交的改动，会看到 stash/pop 的过程

- [ ] **步骤 3：测试未提交改动时的 stash 保护**

操作：
```powershell
# 在 dev 分支上修改一个文件但不提交
echo "test" > test-temp.txt
# 运行同步脚本
.\scripts\sync-upstream.ps1
```

预期：
- 看到 "检测到未提交的改动，正在 stash 暂存..."
- 同步流程正常执行
- 最后看到 "恢复 stash 暂存..."
- `test-temp.txt` 仍然存在

清理：
```powershell
Remove-Item test-temp.txt
```

- [ ] **步骤 4：Commit**

```bash
git add scripts/sync-upstream.ps1
git commit -m "feat: add sync-upstream.ps1 for upstream sync workflow"
```

---

### 任务 2：创建 sync-dev.ps1

**文件：**
- 创建：`scripts/sync-dev.ps1`

- [ ] **步骤 1：创建脚本文件并编写完整代码**

```powershell
# sync-dev.ps1 — 在 dev 分支拉取上游更新，展示信息面板，合并由用户手动执行
# 用法: .\scripts\sync-dev.ps1

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

# 检查当前分支
$currentBranch = git branch --show-current
if ($currentBranch -ne "dev") {
    Write-Warn "当前分支是 $currentBranch，不是 dev"
    $answer = Read-Host "  是否切换到 dev 分支？(Y/n)"
    if ($answer -eq "" -or $answer -match "^[Yy]") {
        git checkout dev 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Err "切换到 dev 分支失败"
            exit 1
        }
        $currentBranch = "dev"
    } else {
        Write-Info "保持当前分支，继续拉取上游更新..."
    }
}

# ── 保存现场 ──────────────────────────────────────────

$stashed = $false

$status = git status --porcelain
if ($status) {
    Write-Info "检测到未提交的改动，正在 stash 暂存..."
    git stash push -m "sync-dev-auto-stash" --include-untracked
    if ($LASTEXITCODE -ne 0) {
        Write-Err "stash 失败，请手动处理后重试"
        exit 1
    }
    $stashed = $true
    Write-Ok "已暂存"
}

# ── 主流程 ────────────────────────────────────────────

try {
    # 1. 拉取上游
    Write-Info "从 upstream 拉取最新代码..."
    git fetch upstream 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Err "fetch upstream 失败，请检查网络连接"
        return
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
        Write-Host "  ║  上游新增提交: 0 个（已是最新）          ║" -ForegroundColor Green
    } else {
        Write-Host "  ║  上游新增提交: $upstreamNew 个" -ForegroundColor Yellow
    }

    Write-Host "  ║  你的独立提交: $devOwn 个" -ForegroundColor Cyan
    Write-Host "  ╠══════════════════════════════════════════╣" -ForegroundColor Cyan

    if ($upstreamNew -eq 0) {
        Write-Host "  ║  无需合并，dev 已包含所有上游更新        ║" -ForegroundColor Green
    } else {
        Write-Host "  ║  请手动执行合并:                         ║" -ForegroundColor Cyan
        Write-Host "  ║    git merge upstream/main               ║" -ForegroundColor White
        Write-Host "  ║                                          ║" -ForegroundColor Cyan
        Write-Host "  ║  如有冲突:                               ║" -ForegroundColor Cyan
        Write-Host "  ║    1. 解决冲突文件                       ║" -ForegroundColor Cyan
        Write-Host "  ║    2. git add <已解决的文件>              ║" -ForegroundColor Cyan
        Write-Host "  ║    3. git merge --continue               ║" -ForegroundColor Cyan
    }

    Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

} finally {
    # ── 恢复现场 ──────────────────────────────────────

    if ($stashed) {
        Write-Info "恢复 stash 暂存..."
        git stash pop 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "stash pop 失败，请手动执行: git stash pop"
        }
    }
}
```

- [ ] **步骤 2：在 dev 分支上运行脚本验证基本流程**

运行：
```powershell
.\scripts\sync-dev.ps1
```

预期：
- 看到信息面板，显示上游新增提交数和本地独立提交数
- 如果上游有更新，面板会提示手动执行 `git merge upstream/main`
- 如果已是最新，面板显示绿色 "无需合并"
- 不会自动执行任何 merge 操作

- [ ] **步骤 3：测试非 dev 分支时的切换提示**

操作：
```powershell
# 先切到 main
git checkout main
# 运行脚本
.\scripts\sync-dev.ps1
```

预期：
- 看到 "当前分支是 main，不是 dev"
- 提示 "是否切换到 dev 分支？(Y/n)"
- 输入 Y 后自动切换到 dev 并继续
- 输入 n 后保持 main 分支继续拉取

清理：
```powershell
git checkout dev
```

- [ ] **步骤 4：Commit**

```bash
git add scripts/sync-dev.ps1
git commit -m "feat: add sync-dev.ps1 for upstream sync workflow"
```

---

### 任务 3：端到端验证

**文件：** 无新文件

- [ ] **步骤 1：完整运行一次同步流程**

依次执行：
```powershell
# 第 1 步：同步上游到 main
.\scripts\sync-upstream.ps1

# 第 2 步：拉取上游更新到 dev
.\scripts\sync-dev.ps1

# 第 3 步：手动合并（根据面板提示）
git merge upstream/main
```

预期：
- 脚本 1 成功同步 main 并推送
- 脚本 2 显示信息面板，提交数正确
- 手动 merge 成功（或需要解决冲突后继续）
- 最终 dev 分支包含上游最新代码 + 你的个性化提交

- [ ] **步骤 2：验证合并后 dev 分支状态**

运行：
```powershell
# 检查 dev 是否包含所有上游提交
git log upstream/main..dev --oneline
# 上面应只显示你自己的提交

git log dev..upstream/main --oneline
# 上面应为空（0 个提交），说明上游代码已全部合入
```

预期：
- 第一条命令只显示你个性化的提交
- 第二条命令输出为空，表示没有遗漏的上游提交

- [ ] **步骤 3：最终 Commit（如有微调）**

```bash
# 如果在验证过程中做了任何调整
git add -A
git commit -m "chore: finalize sync scripts after e2e verification"
```
