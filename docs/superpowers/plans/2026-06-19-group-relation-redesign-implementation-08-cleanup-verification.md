# 分组关联重设计执行分片 08：旧列清理与最终验证

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此分片。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 在新链路稳定后删除旧字符串列，并完成后端、前端和人工验证闭环。

**架构：** 本分片对应阶段 `5`。先处理兼容性最敏感的旧列清理，再运行测试、类型检查、构建和启动验证，最后做人工流程检查。

**技术栈：** Go 1.22+、GORM v2、React 19、Bun

---

## 分片边界

- **范围：** 阶段 `5` 全部任务
- **依赖：** 依赖前 `7` 个分片全部完成，否则不能安全清理旧列。
- **主计划：** [2026-06-19-group-relation-redesign-implementation.md](./2026-06-19-group-relation-redesign-implementation.md)

## 文件

- 修改：`model/main.go`
- 创建：`model/group_test.go`
- 创建：`model/group_migration_test.go`
- 创建：`controller/group_id_test.go`
- 创建：`service/group_id_test.go`
- 修改：`middleware/auth_test.go`
- 修改：`middleware/distributor_test.go`

## 任务 5-1：清理旧字符串列

- [ ] 使用 GORM `Migrator().DropColumn`
- [ ] 删除：
  - `users.group`
  - `tokens.group`
  - `channels.group`
  - `abilities.group`
  - `subscription_plans.upgrade_group`
  - `subscription_plans.downgrade_group`
  - `user_subscriptions.upgrade_group`
  - `user_subscriptions.downgrade_group`

## 任务 5-2：补齐测试

- [ ] 分组模型测试
- [ ] 迁移测试
- [ ] 分组 API 测试
- [ ] `auth` / `distributor` 路径回归测试

## 任务 5-3：最终验证

- [ ] `go test ./... -v`
- [ ] `cd web && bun test`
- [ ] `cd web && bun run typecheck`
- [ ] `cd web && bun run build:check`
- [ ] `go build -o new-api ./cmd/server`
- [ ] 后端启动自检
- [ ] 人工检查：
  - 分组管理页增删改查
  - 用户分组下拉
  - 渠道分组多选
  - Token 模式切换
  - 订阅计划分组下拉
  - 分组倍率生效
  - 改名跟随
  - 停用不再路由
