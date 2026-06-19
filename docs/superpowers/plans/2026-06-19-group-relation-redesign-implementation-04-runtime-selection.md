# 分组关联重设计执行分片 04：运行时缓存与按 group_id 选渠道

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此分片。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 把运行时链路从字符串分组切到 `group_id`，覆盖用户、Token、渠道缓存、能力查询和中间件。

**架构：** 本分片聚焦阶段 `1`。缓存结构、选渠道逻辑、middleware context 和 relay info 一次切到 ID 路径，保证请求链路可以在迁移后继续工作。

**技术栈：** Go 1.22+、GORM v2

---

## 分片边界

- **范围：** 阶段 `1` 全部任务
- **依赖：** 依赖阶段 `0` 的模型、迁移和缓存能力已经可用。
- **主计划：** [2026-06-19-group-relation-redesign-implementation.md](./2026-06-19-group-relation-redesign-implementation.md)

## 文件

- 修改：`model/user.go`
- 修改：`model/user_cache.go`
- 修改：`model/token.go`
- 修改：`model/channel_cache.go`
- 修改：`model/channel.go`
- 修改：`model/ability.go`
- 修改：`service/channel_select.go`
- 修改：`middleware/auth.go`
- 修改：`middleware/distributor.go`
- 修改：`relay/common/relay_info.go`

## 任务

- [ ] **任务 1-1：修改 `User` / `UserBase` / `Token`**
  - `model/user.go` 新增 `GroupId`
  - `model/user_cache.go` 把 `UserBase.Group` 改成 `UserBase.GroupID`
  - `model/token.go` 新增 `GroupMode`、`GroupId`，保留旧 `Group` 仅做迁移期兼容

- [ ] **任务 1-2：修改渠道缓存**
  - `group2model2channels` 的 key 从 `string` 改为 `int`
  - `InitChannelCache` 从 `channel_groups` 构建
  - `GetRandomSatisfiedChannel` 改成接收 `groupID int`

- [ ] **任务 1-2b：补齐活跃引用过滤**
  - `ApplyChannelGroupFilter` 从逗号串匹配切到 `channel_groups` 关系查询
  - 用户搜索从 `users.group` 字符串过滤改为 `users.group_id`

- [ ] **任务 1-3：修改 `Ability` 和选渠道逻辑**
  - `Ability` 新增 `GroupId`
  - `getChannelQuery`、`GetChannel` 按 `group_id` 查询
  - `service/channel_select.go` 通过 context key 解析 `user_group_id`、`token_group_id`、`token_group_mode`

- [ ] **任务 1-4：修改中间件**
  - `middleware/auth.go` 写入 `ContextKeyUserGroupID`、`ContextKeyTokenGroupID`、`ContextKeyTokenGroupMode`、`ContextKeyUsingGroupID`
  - `middleware/distributor.go` 使用 `using_group_id`

- [ ] **任务 1-5：修改 `RelayInfo`**
  - `TokenGroup`、`UsingGroup`、`UserGroup` 改为基于 ID 的字段

## 本片验收

- [ ] `go test ./middleware/... ./service/...`
- [ ] 请求链路中可以从 `context` 读到最终 `using_group_id`
- [ ] 选渠道逻辑不再依赖字符串分组
