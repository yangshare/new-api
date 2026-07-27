# 分组关联重设计（Group Relation Redesign）执行主计划

> **面向 AI 代理的工作者：** 执行时只加载本主计划和当前分片。不要把全部分片一次性塞进同一个实现会话。步骤继续使用复选框（`- [ ]`）语法在分片文档中跟踪。

**目标：** 引入独立的 `groups` 实体表，所有活跃引用从字符串改为按 `group_id` 引用。改名只改 `groups.name` 一行，所有引用自动跟随。

**架构：** 保留原方案 A 的关系模型与迁移路径，但把执行文档拆为 `1` 份主计划加 `8` 份执行分片。主计划负责共享约束、依赖顺序和全局命名；分片负责当前阶段的改动文件、任务边界和验证入口。

**技术栈：** Go 1.22+、GORM v2、SQLite / MySQL / PostgreSQL、React 19、TypeScript、Bun

---

## 分片说明

原始实现计划超过 `3,000` 行，直接拿整份文档驱动实现，容易在单次执行里叠加源码、diff、测试输出和报错日志，最终撑爆上下文。现在改为：

- `1` 份主计划：保留共享背景、约束、依赖和执行入口。
- `8` 份执行分片：每次只处理一个分片，阶段切换时再加载下一个。

## 执行顺序

| 顺序 | 分片文件 | 范围 | 进入下一片的前置条件 |
|---|---|---|---|
| 1 | [01-schema-cache](./2026-06-19-group-relation-redesign-implementation-01-schema-cache.md) | 任务 `0-1`、`0-1b` | 新模型、关系表、缓存骨架可编译 |
| 2 | [02-migration-framework](./2026-06-19-group-relation-redesign-implementation-02-migration-framework.md) | 任务 `0-2` 的 `v2 步骤 0-2` | 迁移入口、幂等判据、事务边界落地 |
| 3 | [03-migration-backfill-tests](./2026-06-19-group-relation-redesign-implementation-03-migration-backfill-tests.md) | 任务 `0-2` 的剩余步骤 + `0-3` | 数据回填、关系迁移、迁移测试可跑 |
| 4 | [04-runtime-selection](./2026-06-19-group-relation-redesign-implementation-04-runtime-selection.md) | 阶段 `1` | 运行时按 `group_id` 选渠道闭环完成 |
| 5 | [05-ratio-settings](./2026-06-19-group-relation-redesign-implementation-05-ratio-settings.md) | 阶段 `2` | 倍率、可用组、限流全部按 ID 读取 |
| 6 | [06-api-contracts](./2026-06-19-group-relation-redesign-implementation-06-api-contracts.md) | 阶段 `3` | 管理 API 和业务入参切到 ID 合同 |
| 7 | [07-frontend](./2026-06-19-group-relation-redesign-implementation-07-frontend.md) | 阶段 `4` | `web` 完成表单和页面改造 |
| 8 | [08-cleanup-verification](./2026-06-19-group-relation-redesign-implementation-08-cleanup-verification.md) | 阶段 `5` | 清理旧列并完成最终验证 |

## 执行规则

- 单次实现只读取：`主计划 + 当前分片 + 当前要改的源码`。
- 阶段边界不能跳。尤其是阶段 `0` 的 `3` 个分片，必须按顺序执行。
- 字段命名统一使用 `group_id`、`group_mode`、`group_ids`。不要在后续分片重新发明命名。
- 共享约束、跨库兼容要求、Context Key、全局常量、保留列策略，都以本主计划为准。
- 分片内若出现与本主计划冲突的旧内容，以本主计划中的 `v2 修订说明` 为准。

## v2 修订说明（2026-06-19 评审修复）

- **迁移幂等判据：** 不再依赖 `groups` 表是否存在，改用 `users.group_id` 和 `schema_migrations` 版本标记。
- **迁移事务一致性：** 所有迁移期读写统一通过 `tx *gorm.DB`，禁止迁移过程调用基于全局 `DB` 的 helper。
- **跨库兼容：** 表存在性检查和列删除必须兼容 SQLite、MySQL、PostgreSQL。
- **软删除 vs 停用：** `Group` 仅保留 `status` 语义，移除 `gorm.DeletedAt`；删除走物理删除 + 关联清理。
- **Ability 主键过渡：** 迁移期主键直接切为 `(group_id, model, channel_id)`，旧 `group` 列仅作回退索引。
- **循环依赖：** `common/group.go` 只保留无依赖工具；分组编排逻辑放入 `service/group_id.go`。
- **活跃引用补全：** `ApplyChannelGroupFilter`、`SearchUsers` 等仍按旧字符串过滤的路径必须一并切到 ID。
- **group_usable_groups 语义：** 引入 `is_global`，分别承载全局白名单和按用户组的特殊可用关系。
- **auto 分组迁移：** 旧 `autoGroups` 落为 `groups.auto_selectable=true`，运行时再叠加可用组过滤。
- **group_cache：** 新增 `model/group_cache.go`，热路径通过缓存做 `group_id ↔ name`、倍率和限流读取。
- **前端栈纠正：** 阶段 `4` 统一按 `web` 实际栈实现，不引入 `antd`。
- **RetryParam：** 保持现有结构，分组信息通过 `Ctx` 里的 context key 传递。
- **RateLimit 指针透传：** 管理列表直接透传模型上的 `*int` 指针，不在 controller 里构造局部变量地址。
- **管理列表含停用组：** `GetGroups` 面向管理端返回全部分组；启用态过滤另行处理。

## 阶段依赖图

```text
阶段 0（数据模型+迁移） -> 阶段 1（缓存+选渠道） -> 阶段 2（倍率+配置） -> 阶段 3（API） -> 阶段 4（前端） -> 阶段 5（清理+验证）
      ↓                        ↓                        ↓                   ↓
  迁移测试通过              缓存测试通过              配置测试通过         API 测试通过
```

## 全局约定

### 新增常量

| 常量 | 位置 | 值 | 说明 |
|---|---|---|---|
| `GroupStatusEnabled` | `constant/group.go` | `1` | 分组启用 |
| `GroupStatusDisabled` | `constant/group.go` | `2` | 分组停用 |
| `GroupModeInherit` | `constant/group.go` | `"inherit"` | Token 跟随用户 |
| `GroupModeFixed` | `constant/group.go` | `"fixed"` | Token 固定分组 |
| `GroupModeAuto` | `constant/group.go` | `"auto"` | Token 自动分组 |

### 新增 Context Keys

| 常量 | 位置 | 值 | 说明 |
|---|---|---|---|
| `ContextKeyUsingGroupID` | `constant/context_key.go` | `"using_group_id"` | 最终使用的分组 ID |
| `ContextKeyUserGroupID` | `constant/context_key.go` | `"user_group_id"` | 用户分组 ID |
| `ContextKeyTokenGroupID` | `constant/context_key.go` | `"token_group_id"` | Token 分组 ID |
| `ContextKeyTokenGroupMode` | `constant/context_key.go` | `"token_group_mode"` | Token 分组模式 |
| `ContextKeyAutoGroupID` | `constant/context_key.go` | `"auto_group_id"` | auto 模式最终选中的分组 ID |

### 保留与清理边界

- `users.group`、`tokens.group`、`channels.group`、`abilities.group`、订阅相关旧字符串列：迁移后删除。
- `logs.group`、`tasks.group`、`perf_metric.group`：保留为历史快照，不做 ID 化。

## 文件结构总览

### 新增文件

- `model/group.go`
- `model/channel_group.go`
- `model/group_usable_group.go`
- `model/group_group_ratio.go`
- `model/group_migration.go`
- `model/group_cache.go`
- `service/group_id.go`
- `controller/group_id.go`
- `web/src/features/system-settings/lib/group-api.ts`
- `web/src/features/system-settings/types/group.ts`

### 关键修改文件

- `model/main.go`
- `model/user.go`
- `model/user_cache.go`
- `model/token.go`
- `model/channel.go`
- `model/ability.go`
- `model/channel_cache.go`
- `middleware/auth.go`
- `middleware/distributor.go`
- `service/group.go`
- `service/channel_select.go`
- `service/quota.go`
- `controller/user.go`
- `controller/channel.go`
- `controller/token.go`
- `controller/subscription.go`
- `router/api-router.go`
- `setting/ratio_setting/group_ratio.go`
- `setting/user_usable_group.go`
- `setting/auto_group.go`
- `setting/rate_limit.go`

## 执行交接

计划已拆分为 `1` 份主计划和 `8` 份执行分片。后续实现时，优先选择分片驱动，而不是重新把整份原计划拼回一个会话。
﻿
