# 分组关联重设计执行分片 06：管理 CRUD 与业务 API 入参切换

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此分片。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 为 `groups` 提供完整管理 CRUD，并把用户、渠道、Token、订阅等外部 API 合同改成按 ID 入参。

**架构：** 本分片聚焦阶段 `3`。先新增分组管理 API，再把既有 controller 入参与校验逻辑切到 `group_id` / `group_ids` / `group_mode`。管理接口和用户可选接口的返回范围要区分。

**技术栈：** Go 1.22+、Gin、GORM v2

---

## 分片边界

- **范围：** 阶段 `3` 全部任务
- **依赖：** 依赖分片 `05-ratio-settings` 已稳定产出按 ID 的业务读取函数。
- **主计划：** [2026-06-19-group-relation-redesign-implementation.md](./2026-06-19-group-relation-redesign-implementation.md)

## 文件

- 创建：`controller/group_id.go`
- 修改：`router/api-router.go`
- 修改：`controller/user.go`
- 修改：`controller/channel.go`
- 修改：`controller/token.go`
- 修改：`controller/subscription.go`

## 任务 3-1：新增分组管理 CRUD API

- [ ] **v2 步骤 0：修正管理列表语义**
  - `GetGroups` 面向管理端返回 enabled / disabled 全部分组
  - `RateLimitTotal` / `RateLimitSuccess` 直接透传模型指针

- [ ] **v2 步骤 0b：删除分组使用事务清理关联**
  - 清理 `channel_groups`
  - 清理 `abilities`
  - 物理删除 `groups` 行
  - 成功后刷新 `group_cache`

- [ ] **步骤 1：编写 CRUD controller**
  - `GetGroups`
  - `CreateGroup`
  - `UpdateGroup`
  - `DeleteGroup`

- [ ] **步骤 2：注册路由**
  - `GET /api/group/`
  - `POST /api/group/`
  - `PUT /api/group/:id`
  - `DELETE /api/group/:id`

## 任务 3-2：修改用户 / 渠道 / Token / 订阅 API

- [ ] **步骤 1：用户 API 改为 `group_id`**
- [ ] **步骤 2：渠道 API 改为 `group_ids`**
- [ ] **步骤 3：Token API 改为 `group_mode + group_id`**
- [ ] **步骤 4：订阅计划 API 改为 `upgrade_group_id / downgrade_group_id`**

## 本片验收

- [ ] `go test ./controller/... ./router/...`
- [ ] 管理端能新增、编辑、删除分组
- [ ] 用户、渠道、Token、订阅相关入参不再接受旧字符串分组
