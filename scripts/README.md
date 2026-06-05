# scripts 使用说明

本目录包含本地维护 fork 与上游仓库同步的辅助脚本。建议在仓库根目录执行以下命令。

## 前置条件

- 使用 PowerShell 执行脚本。
- 本地已配置 `origin`，指向自己的 fork。
- 本地已配置 `upstream`，指向上游仓库。

如果尚未配置 `upstream`，先执行：

```powershell
git remote add upstream <上游仓库 URL>
```

可用以下命令确认 remote 配置：

```powershell
git remote -v
```

## 同步上游到 main

使用 `sync-upstream.ps1` 将 `upstream/main` 快进同步到本地 `main`，并推送到 `origin/main`：

```powershell
.\scripts\sync-upstream.ps1
```

脚本行为：

- 自动暂存当前未提交改动（包含未跟踪文件），结束后恢复。
- 自动切换到 `main`，执行 `git fetch upstream`。
- 只允许 `git merge --ff-only upstream/main`，避免在 `main` 上生成额外合并提交。
- 快进成功后执行 `git push origin main`。
- 如果推送失败，会保留本地 `main` 的同步结果，并提示稍后手动执行 `git push origin main`。
- 如果当前处于 detached HEAD，脚本会拒绝执行，避免无法安全恢复现场。

## 检查 dev 与上游差异

使用 `sync-dev.ps1` 在 `dev` 分支拉取上游信息，并显示 `dev` 与 `upstream/main` 的提交差异：

```powershell
.\scripts\sync-dev.ps1
```

脚本行为：

- 如果当前不在 `dev`，会询问是否切换到 `dev`。
- 如果拒绝切换，脚本会退出，不会在当前分支提示合并上游。
- 自动暂存当前未提交改动（包含未跟踪文件），结束后恢复。
- 执行 `git fetch upstream` 后显示上游新增提交数和当前分支独立提交数。
- 不会自动执行合并；如需合并，按脚本提示手动执行可审查合并：

```powershell
git merge --no-commit --no-ff upstream/main
```

执行后先检查自动合并结果：

```powershell
git status
git diff --cached
git diff
```

如果出现冲突，按 Git 提示解决冲突后执行：

```powershell
git add <已解决的文件>
git commit
```

如果不接受合并结果，执行 `git merge --abort` 放弃本次合并。

## 推荐同步流程

通常按以下顺序执行：

```powershell
.\scripts\sync-upstream.ps1
.\scripts\sync-dev.ps1
```

确认 `sync-dev.ps1` 提示需要合并后，再在 `dev` 分支手动执行：

```powershell
git merge --no-commit --no-ff upstream/main
```

这个命令不会自动提交合并结果。Git 能自动合并的文件会进入待提交状态，无法自动合并的文件会进入冲突状态；你可以检查、修改后再 `git commit`，也可以用 `git merge --abort` 放弃。

## 脚本测试

`sync-script-tests.ps1` 会创建临时 Git 仓库，验证同步脚本的关键安全场景：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\sync-script-tests.ps1 -ScriptRoot (Resolve-Path .\scripts)
```

测试覆盖：

- `sync-dev.ps1` 在非 `dev` 分支且用户拒绝切换时不会提示合并。
- `sync-dev.ps1` 只提示可审查合并命令，不提示普通 merge。
- `sync-upstream.ps1` 推送失败时不会显示同步完成。
- `sync-upstream.ps1` 在 detached HEAD 下拒绝执行。
