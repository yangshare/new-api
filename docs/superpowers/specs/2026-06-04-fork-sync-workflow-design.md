# Fork 上游同步工作流设计

## 目标

在 fork 项目中同步上游更新，同时保留 `dev` 分支上的个性化开发能力。同步入口收敛为一个脚本，避免 `main` 镜像同步和 `dev` 合并流程并存造成误用。

## 分支模型

```
upstream/main  ──●──●──●──●──●──●──    母仓持续更新
                  \        \      \
your dev       ──●──●──●──●──●──●──    你的开发分支
                           ↑ no-commit merge upstream/main
```

| 分支 | 角色 | 维护者 |
|---|---|---|
| `upstream/main` | 母仓 | 上游作者 |
| `dev` | 日常开发 + 打包部署 | `sync-dev.ps1` + 人工审查 |

## 分支规则

- **dev**：所有个性化开发都在这里，也是打包镜像的分支。
- 合并上游时保留人工审查点，不自动提交。

## 脚本设计

### `scripts/sync-dev.ps1`

**用途**：在 `dev` 分支拉取上游更新，并执行可审查的 no-commit merge。

**执行流程**：

1. 检查当前是否在 `dev` 分支；如果不在，提示并询问是否切换。
2. 执行 `git fetch upstream`。
3. 显示上游新增提交数和当前分支独立提交数。
4. 如果工作区不干净，退出并提示用户先处理本地修改。
5. 如果存在上游新增提交，执行：

```powershell
git merge --no-commit --no-ff upstream/main
```

6. 停在提交前，供 IDEA 审查变更或解决标准 Git 冲突。

## 日常工作流

```powershell
.\scripts\sync-dev.ps1
git status
git diff --cached
git diff
```

如果接受合并结果：

```powershell
git commit
```

如果不接受合并结果：

```powershell
git merge --abort
```

## 技术约束

- **脚本格式**：PowerShell（`.ps1`）
- **合并策略**：merge（不使用 rebase）
- **提交策略**：脚本自动 merge，但不自动 commit
- **脚本位置**：`scripts/` 目录下

## 文件清单

| 文件 | 用途 |
|---|---|
| `scripts/sync-dev.ps1` | 为 `dev` 拉取上游更新并执行 no-commit merge |
