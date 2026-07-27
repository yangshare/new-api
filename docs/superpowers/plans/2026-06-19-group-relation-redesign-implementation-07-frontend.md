# 分组关联重设计执行分片 07：web 前端改造

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此分片。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 让 `web` 的分组管理、用户、渠道、Token、订阅和倍率编辑器全部切到 ID 化交互。

**架构：** 本分片只处理阶段 `4` 的前端工作，遵循项目现有的 React 19、Base UI、Tailwind、`react-hook-form` 模式，不引入额外 UI 框架。

**技术栈：** React 19、TypeScript、Base UI、Tailwind、Bun

---

## 分片边界

- **范围：** 阶段 `4` 全部任务
- **依赖：** 依赖分片 `06-api-contracts` 先稳定 API 合同。
- **主计划：** [2026-06-19-group-relation-redesign-implementation.md](./2026-06-19-group-relation-redesign-implementation.md)

## v2 前端约束

- `web` 使用 `react-hook-form`
- 使用 `@/components/ui/form`
- 使用 `@/components/ui/select`
- 多选使用 `MultiSelect`
- 不要使用 `Form.Item`
- 不要使用 `Select.Option`
- 不要引入 `antd` 或 Semi Design API

## 文件

- 创建：`web/src/features/system-settings/pages/group-management-page.tsx`
- 创建：`web/src/features/system-settings/components/group-management-drawer.tsx`
- 创建：`web/src/features/system-settings/lib/group-api.ts`
- 创建：`web/src/features/system-settings/types/group.ts`
- 修改：`web/src/features/users/lib/user-form.ts`
- 修改：`web/src/features/channels/lib/channel-form.ts`
- 修改：`web/src/features/keys/lib/api-key-form.ts`
- 修改：`web/src/features/subscriptions/lib/plan-form.ts`
- 修改：`web/src/features/system-settings/models/group-ratio-form.tsx`
- 修改：`web/src/features/system-settings/models/group-ratio-visual-editor.tsx`
- 修改：`web/src/features/system-settings/request-limits/rate-limit-visual-editor.tsx`

## 任务

- [ ] **任务 4-1：新增分组管理页面**
  - 定义 `Group`、`CreateGroupRequest`、`UpdateGroupRequest`
  - 实现 `getGroups`、`createGroup`、`updateGroup`、`deleteGroup`
  - 新增分组管理页和编辑抽屉

- [ ] **任务 4-2：修改用户 / 渠道 / Token / 订阅编辑表单**
  - 用户：`group_id`
  - 渠道：`group_ids`
  - Token：`group_mode` + `group_id`
  - 订阅：`upgrade_group_id` / `downgrade_group_id`

- [ ] **任务 4-3：修改倍率 / 限流编辑器**
  - 按 ID 读写 `groups`、`group_group_ratios`、`group_usable_groups`
  - 表格显示名称，提交传 ID

## 本片验收

- [ ] `cd web && bun run typecheck`
- [ ] `cd web && bun run build:check`
- [ ] 分组管理、用户、渠道、Token、订阅表单都能以 ID 正常提交
