# 分组关联重设计执行分片 05：倍率、可用组与限流按 ID 读取

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此分片。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 把倍率、可用组、auto 分组和限流配置从旧 map / 字符串读取切到实体表 + ID 读取。

**架构：** 本分片集中处理阶段 `2` 的配置读取与计费逻辑。完成后，服务层和 `setting` 层不再依赖旧字符串分组做运行时判定。

**技术栈：** Go 1.22+、GORM v2

---

## 分片边界

- **范围：** 阶段 `2` 全部任务
- **依赖：** 依赖分片 `04-runtime-selection` 已完成运行时 `group_id` 传播。
- **主计划：** [2026-06-19-group-relation-redesign-implementation.md](./2026-06-19-group-relation-redesign-implementation.md)

## 文件

- 修改：`service/group.go`
- 修改：`setting/ratio_setting/group_ratio.go`
- 修改：`setting/user_usable_group.go`
- 修改：`setting/auto_group.go`
- 修改：`setting/rate_limit.go`
- 修改：`service/quota.go`

## 任务

- [ ] **任务 2-1：修改分组配置读取函数**
  - `service/group.go`：`GetUserUsableGroups`、`GetUserAutoGroups`、`GetUserGroupRatio`
  - `setting/ratio_setting/group_ratio.go`：按 `groups` / `group_group_ratios` 读取
  - `setting/user_usable_group.go`：按 `group_usable_groups` 读取
  - `setting/auto_group.go`：按 `groups.auto_selectable` 读取
  - `setting/rate_limit.go`：按 `groups.rate_limit_total/rate_limit_success` 读取

- [ ] **任务 2-2：修改倍率计算和日志写入**
  - `service/quota.go` 统一按 `group_id` 算倍率
  - 写日志时通过 `group_cache` 或 `GetGroupNameByID` 反查分组名快照

## 本片验收

- [ ] `go test ./service/... ./setting/...`
- [ ] 倍率、auto 分组、可用组、限流全部不再依赖旧 map
- [ ] 日志仍然能落历史分组名称快照
