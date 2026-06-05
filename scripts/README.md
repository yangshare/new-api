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

## 合并上游到 dev

使用 `sync-dev.ps1` 在 `dev` 分支拉取上游信息，并以可审查方式合并 `upstream/main`：

```powershell
.\scripts\sync-dev.ps1
```

脚本行为：

- 如果当前不在 `dev`，会询问是否切换到 `dev`。
- 如果拒绝切换，脚本会退出，不会在当前分支合并上游。
- 执行 `git fetch upstream` 后显示上游新增提交数和当前分支独立提交数。
- 如果工作区不干净，脚本会退出，避免把已有本地修改和上游合并混在一起。
- 如果存在上游新增提交，脚本会自动执行可审查合并：

```powershell
git merge --no-commit --no-ff upstream/main
```

这个命令不会自动提交。Git 能自动合并的文件会进入待提交状态，冲突文件会进入标准 Git 冲突状态，IDEA 可以直接显示和处理这些改动。

合并后先检查结果：

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

通常只需要执行：

```powershell
.\scripts\sync-dev.ps1
```

`sync-dev.ps1` 会在需要时自动执行 no-commit merge。你可以检查、修改后再 `git commit`，也可以用 `git merge --abort` 放弃。

## 脚本测试

`sync-script-tests.ps1` 会创建临时 Git 仓库，验证同步脚本的关键安全场景：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\sync-script-tests.ps1 -ScriptRoot (Resolve-Path .\scripts)
```

测试覆盖：

- `sync-dev.ps1` 在非 `dev` 分支且用户拒绝切换时不会提示合并。
- `sync-dev.ps1` 会执行 no-commit merge，并停在提交前供人工审查。
- `sync-dev.ps1` 不使用 reject patch 流程生成 `.rej` 文件。
