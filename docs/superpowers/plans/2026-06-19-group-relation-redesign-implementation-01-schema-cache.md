# 分组关联重设计执行分片 01：数据模型、关系表与分组缓存

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此分片。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 落地 `groups` 实体、关系表、基础常量和 `group_cache`，为迁移和运行时改造提供底座。

**架构：** 本分片只处理阶段 `0` 的建模部分，不碰迁移回填和运行时读路径。代码层先建立 `groups`、`channel_groups`、`group_usable_groups`、`group_group_ratios` 和 `group_cache`，再把新模型注册进 `AutoMigrate`。

**技术栈：** Go 1.22+、GORM v2、SQLite / MySQL / PostgreSQL

---

## 分片边界

- **范围：** 任务 `0-1`、`0-1b`
- **依赖：** 无。它是整个重设计的第一个执行单元。
- **主计划：** [2026-06-19-group-relation-redesign-implementation.md](./2026-06-19-group-relation-redesign-implementation.md)

## 文件

- 创建：`model/group.go`
- 创建：`model/channel_group.go`
- 创建：`model/group_usable_group.go`
- 创建：`model/group_group_ratio.go`
- 创建：`model/group_cache.go`
- 创建：`constant/group.go`
- 创建：`common/group.go`
- 创建：`service/group_id.go`
- 修改：`model/main.go`

## 任务 0-1：创建分组实体模型与关联表

- [ ] **步骤 1：编写 `Group` 实体模型**
  - `Group` 仅保留 `status` 停用语义，移除 `gorm.DeletedAt`。
  - `name` 使用普通 `index`，唯一性改到应用层校验。
  - 补齐 `GetGroupByName`、`GetGroupByID`、`GetDefaultGroup`、`GetEnabledGroups`、`GetAllGroups`、`GetAutoSelectableGroups`、`GetGroupRateLimit`。

- [ ] **步骤 2：编写 `ChannelGroup` 关联模型**
  - 提供 `GetChannelGroupIDs`、`GetChannelIDsByGroup`、`UpsertChannelGroups`。
  - 主键使用 `(channel_id, group_id)`，不依赖字符串分组。

- [ ] **步骤 3：编写 `GroupUsableGroup` 模型**
  - 引入 `is_global`，区分全局白名单和按用户组的特殊可用关系。
  - 提供 `GetUserUsableGroupIDs`、`CheckUserCanUseGroup`。

- [ ] **步骤 4：编写 `GroupGroupRatio` 模型**
  - 提供 `GetUserGroupRatio`、`GetUserGroupRatios`。

- [ ] **步骤 5：定义分组常量**
  - `GroupStatusEnabled`
  - `GroupStatusDisabled`
  - `GroupModeInherit`
  - `GroupModeFixed`
  - `GroupModeAuto`

- [ ] **步骤 6：拆分无依赖工具与业务解析**
  - `common/group.go` 只放无依赖工具，例如 `NormalizeGroupMode`。
  - `service/group_id.go` 承接 `ResolveEffectiveGroupID`、`GetDefaultGroupID` 等需要访问 `model` 的逻辑。

- [ ] **步骤 7：注册到 `AutoMigrate`**
  - 把 `Group`、`ChannelGroup`、`GroupUsableGroup`、`GroupGroupRatio` 加入 `model/main.go`。

## 任务 0-1b：实现分组缓存

- [ ] **步骤 1：创建 `model/group_cache.go`**
  - 缓存 `id -> name`
  - 缓存 `name -> id`
  - 缓存 `id -> group_ratio`
  - 缓存 `id -> topup_ratio`
  - 缓存 `id -> rate_limit`
  - 提供 `RefreshGroupCache`、`GetGroupNameByIDCached`、`GetGroupIDByNameCached`、`GetGroupRatioCached`

- [ ] **步骤 2：接入刷新点**
  - `AutoMigrate` 和迁移完成后刷新
  - `CreateGroup`、`UpdateGroup`、`DeleteGroup` 成功提交后刷新
  - 刷新失败要返回错误给管理 API，不能静默吞掉

## 本片验收

- [ ] `go test ./model/... ./service/...`
- [ ] `groups` 及三张关系表能通过 `AutoMigrate`
- [ ] `group_cache` 提供热路径读取 helper
