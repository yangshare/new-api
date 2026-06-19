# 分组关联重设计执行分片 02：迁移框架、幂等保护与事务边界

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此分片。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 先把一次性迁移的外壳搭稳，明确 version 标记、幂等判据、`tx` helper 和事务提交边界。

**架构：** 本分片只实现迁移框架本身，不展开具体数据回填。核心是让 `RunGroupMigration` 能以正确的 `schema_migrations` 标记、`users.group_id` 幂等判据和全程 `tx *gorm.DB` 运行。

**技术栈：** Go 1.22+、GORM v2、SQLite / MySQL / PostgreSQL

---

## 分片边界

- **范围：** 任务 `0-2` 的 `v2 步骤 0-2`
- **依赖：** 依赖分片 `01-schema-cache` 中的新模型已经存在。
- **主计划：** [2026-06-19-group-relation-redesign-implementation.md](./2026-06-19-group-relation-redesign-implementation.md)

## 文件

- 创建：`model/group_migration.go`
- 修改：`model/main.go`

## 任务 0-2：编写一次性迁移函数

- [ ] **v2 步骤 0：定义迁移期 `tx` 查询 helper**
  - `SchemaMigration`
  - `groupRelationMigrationVersion`
  - `getGroupByNameTx`
  - `getGroupByIDTx`
  - `groupIDByNameTx`

- [ ] **v2 步骤 1：使用正确的幂等判据**
  - 先 `AutoMigrate(&SchemaMigration{})`
  - 优先检查 `schema_migrations.version`
  - 再检查 `users.group_id` 是否存在且已有非零值
  - 禁止再以 `groups` 表是否存在作为“已迁移”判据

- [ ] **v2 步骤 2：迁移函数全程使用 `tx`**
  - `RunGroupMigration` 入口统一开启事务
  - `scanUniqueGroupNames`、`upsertGroups`、`migrateGroupConfigs`、`backfillActiveReferences`、`buildChannelGroups`、`rebuildAbilities`、`verifyMigration` 全部显式接收 `tx`
  - 事务提交前写入 `SchemaMigration` 版本标记

## 本片验收

- [ ] `RunGroupMigration` 在未迁移时可以进入事务
- [ ] 重复执行时能被 `schema_migrations` / `users.group_id` 幂等保护拦住
- [ ] 迁移过程不再调用基于全局 `DB` 的 helper
