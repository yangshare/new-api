# 分组关联重设计执行分片 03：迁移回填、关系重建与迁移测试

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此分片。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 完成迁移期的数据回填、配置迁移、`channel_groups` / `abilities` 重建，以及迁移层测试闭环。

**架构：** 在迁移框架稳定后，本分片继续实现 `migrateGroupConfigs`、`backfillActiveReferences`、`buildChannelGroups`、`rebuildAbilities` 和导出 helper，再补上迁移测试，确保迁移具有可验证的回归保护。

**技术栈：** Go 1.22+、GORM v2、SQLite / MySQL / PostgreSQL

---

## 分片边界

- **范围：** 任务 `0-2` 的剩余步骤，以及任务 `0-3`
- **依赖：** 依赖分片 `02-migration-framework` 已经落地迁移入口、helper 和事务框架。
- **主计划：** [2026-06-19-group-relation-redesign-implementation.md](./2026-06-19-group-relation-redesign-implementation.md)

## 文件

- 修改：`model/group_migration.go`
- 修改：`common/topup-ratio.go`
- 修改：`setting/ratio_setting/group_ratio.go`
- 创建：`model/group_migration_test.go`

## 任务 0-2：补齐迁移主体

- [ ] **v2 步骤 3：正确迁移全局 / 特殊可用组配置**
  - `ratio_setting.GetGroupGroupRatioCopy()` -> `group_group_ratios`
  - `setting.GetUserUsableGroupsCopy()` -> `group_usable_groups`，`is_global=true`
  - `ratio_setting.GetGroupSpecialUsableGroupCopy()` -> `group_usable_groups`，`is_global=false`

- [ ] **v2 步骤 4：补齐订阅回填**
  - 同步回填 `subscription_plans.upgrade_group_id`
  - 同步回填 `subscription_plans.downgrade_group_id`
  - 同步回填 `user_subscriptions.upgrade_group_id`
  - 同步回填 `user_subscriptions.downgrade_group_id`
  - 同步回填 `user_subscriptions.prev_user_group_id`
  - 非空旧值找不到分组时必须回滚

- [ ] **步骤 1：完成迁移函数骨架中的具体子函数**
  - `scanUniqueGroupNames`
  - `upsertGroups`
  - `backfillActiveReferences`
  - `buildChannelGroups`
  - `rebuildAbilities`
  - `verifyMigration`
  - `dryRunMigration`

- [ ] **步骤 2：补导出 helper**
  - `common.TopupGroupRatioCopy()`
  - `ratio_setting.GetGroupGroupRatioCopy()`
  - `ratio_setting.GetGroupSpecialUsableGroupCopy()`

## 任务 0-3：编写迁移测试

- [ ] **步骤 1：补齐迁移测试**
  - 幂等性
  - dry-run
  - 唯一分组名扫描
  - `abilities` 重建保真
  - 改名跟随
  - token `inherit/fixed/auto`
  - 停用后的回退路径

## 本片验收

- [ ] `go test ./model -run GroupMigration -v`
- [ ] 迁移可以从旧字符串数据完整回填到 ID 关系
- [ ] `dryRunMigration` 至少输出将创建的关键统计
