# 分组关联重设计（Group Relation Redesign）

- **日期**：2026-06-19
- **状态**：草案，待审查
- **作者**：AI 辅助生成（遵循项目 Rule 8 声明）
- **背景**：当前 `group` 是散落在各表的裸字符串，没有独立的分组实体，导致分组改名需要级联扫改所有引用处。

---

## 1. 背景与目标

### 1.1 现状

当前 `group` 以「按值引用」的方式存在——一个裸字符串散落在多张表里，没有独立的分组实体表：

| 表 | 字段 | 形态 |
|---|---|---|
| `users` | `group` | 单字符串，`varchar(64)`，默认 `'default'` |
| `channels` | `group` | **逗号分隔多分组串**，如 `"default,vip,enterprise"` |
| `abilities` | `group` | 复合主键成员 `(group, model, channel_id)`，由 `channel.group × channel.models` 笛卡尔积派生 |
| `token` | `group` | 单字符串，默认 `''`（空表示跟随用户分组） |
| `logs` / `tasks` / `subscription` / `perf_metric` | `group` | 历史/快照，记录「当时」的分组名 |

运行时，`model/channel_cache.go` 的 `InitChannelCache` 把 `channel.group` 拆逗号串 × `channel.models` 构建内存缓存 `group2model2channels map[group]map[model][]int`，选渠道入口 `GetRandomSatisfiedChannel(group, model, ...)` 按 group 名查找。

倍率体系：`setting/ratio.go` 的 `GroupRatio` 是 `RWMap[string]float64`，key 是分组名。

### 1.2 核心痛点

**分组改名需要级联更新所有引用处。** 改一个分组名要扫改：

- `users.group`（精确匹配）
- `channels.group`（逗号串里按分隔符精确替换，且要避免 `vip` / `vip2` 前缀重名误伤）
- `abilities.group`（派生表，需重建）
- `token.group`

根本原因：group 是「按值引用」而非「按 ID 引用」，没有独立的分组实体。

### 1.3 目标

引入独立的 `groups` 实体表，所有**活跃引用**改为按 `group_id` 引用。改名只改 `groups.name` 一行，所有引用自动跟随。

### 1.4 非目标（明确不在范围内）

- **用户多分组**：保持「一个用户一个分组」的现有语义（仅存储从字符串改 ID）。
- **分组层级 / 继承**：不引入父子分组、倍率继承。
- **历史表 ID 化**：`logs` / `tasks` / `subscription` / `perf_metric` 的 `group` 字符串**保持不动**，作为历史快照保留旧名（用户决策）。
- 渠道本身的「多分组」语义不变（仍可属多个分组），只是存储从逗号串改为关联表。

---

## 2. 设计决策汇总

| 维度 | 决策 |
|---|---|
| 历史数据处理 | 保留旧名快照，不参与 ID 化 |
| 分组管理形态 | 分组成为一等实体（独立管理页、完整生命周期、倍率绑定、下拉选择） |
| 删除语义 | 仅停用不真删（软删除） |
| 目标数据模型 | **方案 A：规范关系模型**——`groups` 实体表 + `channel_groups` 多对多关联表 + 各表 `group_id` 外键 |
| 数据迁移 | **一次性迁移**（维护窗口内完成） |
| 对外 API 入参 | **硬切 `group_id`**，不兼容 group name |
| `default` 分组 | 可改名、不可删（系统保留分组） |
| 倍率存储 | **彻底废弃 `GroupRatio` map**，`groups.group_ratio` / `topup_ratio` 为唯一权威源 |

---

## 3. 目标数据模型

### 3.1 新增 `groups` 实体表

```go
type Group struct {
    Id          int            `json:"id" gorm:"primaryKey"`
    Name        string         `json:"name" gorm:"type:varchar(64);uniqueIndex"`
    Description string         `json:"description" gorm:"type:varchar(255)"`
    Status      int            `json:"status" gorm:"default:1"`   // 1=enabled, 2=disabled，对齐 common.ChannelStatus
    GroupRatio  float64        `json:"group_ratio" gorm:"default:1"`
    TopUpRatio  float64        `json:"topup_ratio" gorm:"default:1"`
    Sort        int            `json:"sort" gorm:"default:0"`
    CreatedTime int64          `json:"created_time" gorm:"bigint"`
    UpdatedTime int64          `json:"updated_time" gorm:"bigint"`
    DeletedAt   gorm.DeletedAt `json:"-" gorm:"index"`            // 软删除
}
```

- `name` 唯一索引；改名只 `UPDATE name`。
- `status`：`enabled` 时参与路由；`disabled`（软删除）后不再路由，但引用保留。
- `group_ratio` / `topup_ratio`：倍率权威源（见 §6）。

### 3.2 A 类活跃引用表（字符串 → ID）

| 表 | 变更 |
|---|---|
| `users` | `group varchar` → **`group_id int`**（index；迁移时回填，新建用户由代码赋 `default` 分组 id，不依赖 DB 动态默认值） |
| `token` | `group varchar` → **`group_id int`**（默认 `0`，**`0` 表示「跟随用户分组」**，语义贯穿调用链） |
| `abilities` | `group varchar`（主键成员）→ **`group_id int`**（主键成员）；主键变为 `(group_id, model, channel_id)` |

### 3.3 渠道多分组：新增 `channel_groups` 关联表

```go
type ChannelGroup struct {
    ChannelId int `json:"channel_id" gorm:"primaryKey;autoIncrement:false"`
    GroupId   int `json:"group_id" gorm:"primaryKey;autoIncrement:false;index"`
}
```

- 复合主键 `(channel_id, group_id)`；`group_id` 加索引以支持「按分组反查渠道」。
- `channels.group` 逗号串列**移除**，多分组改由本表表达。

### 3.4 历史表（不动）

`logs` / `tasks` / `subscription` / `perf_metric` 的 `group varchar` 列**完全保留**，不回填、不 ID 化。按分组统计消费时，改名前后的历史数据会「断开」——这是用户明确接受的取舍。

### 3.5 关键不变量

- **改名**：`UPDATE groups.name` 一行 → `users` / `token` / `abilities` / `channel_groups` 全部自动跟随（都引用 id）——**核心目标达成**。
- **删除 / 停用**：`status=disabled` + `deleted_at`（软删除），引用保留不丢；停用分组不参与路由。
- **abilities 重建**：从 `channel_groups × channels.models` 笛卡尔积派生（替换原来拆分 `channel.group` 逗号串的逻辑）。
- **`default` 分组**：迁移时由字符串 `'default'` 映射而来；可改名、不可删。

> 关于 SQL 保留字：旧列与历史表的 `group` 列仍是保留字，查询沿用 `commonGroupCol` / `commonKeyCol`（`model/main.go`）；新增的 `group_id` 非保留字，反而规避了保留字问题。

---

## 4. 数据迁移（一次性迁移）

### 4.1 前置条件与维护窗口

- 迁移期间进入**维护模式**（拒绝写请求或短暂停服）。
- 迁移前**强制要求 DB 备份**；提供 **dry-run** 预扫描，先列出将创建的唯一分组名清单供人工确认。
- 大表（`users` / `abilities`）回填分批进行，输出进度日志。
- 失败处理：迁移事务失败 → 恢复备份。

### 4.2 7 个原子步骤

1. **建表**：`groups`、`channel_groups`；给 `users` / `token` 增列 `group_id`（遵循 `model/main.go` 的 `ADD COLUMN` 模式，兼容三种 DB；遵循 Rule 2）。`abilities` **不增列**——走步骤 6 的清空重建。
2. **扫描唯一分组名**：从 `users.group`、`channels.group`（拆逗号）、`token.group`（非空）、`abilities.group` 汇总去重。
3. **upsert `groups`**：为每个唯一名建实体；`group_ratio` / `topup_ratio` 取自当前 `GroupRatio` map；`'default'` 作为系统保留分组（`status=enabled`）。
4. **回填 `group_id`**：
   - `users.group_id` = `groups.id where name = users.group`；空值归到 `default`。
   - `token.group_id`：原 `group=''` → `0`（跟随用户）；非空 → 对应 id。
   - （`abilities` 的 `group_id` 在步骤 6 重建时生成，不在此回填。）
5. **建 `channel_groups`**：拆 `channels.group` 逗号串 → 插入 `(channel_id, group_id)`。
6. **重建 `abilities`**（关键简化，见 §4.3）：清空后从 `channel_groups × channels.models` 重新派生，主键直接以 `group_id` 建表——**规避主键列 `varchar→int` 的跨库变更难题**。
7. **切换并清理**：代码读路径切到 `group_id`；删除 `users.group` / `token.group` / `abilities.group`(旧) / `channels.group` 旧字符串列；下线 `GroupRatio` map（见 §6）。恢复服务。

### 4.3 abilities 重建而非 ALTER

`abilities` 的 `group` 既是主键成员又要改类型（`varchar→int`），三库都无法用简单 `ALTER` 改主键。**但 `abilities` 是纯派生表**，因此迁移策略是：

> 维护窗口内 `TRUNCATE abilities` → 用新结构（`group_id` 主键）建表 → 从 `channel_groups × channels.models` 重新生成全部记录。

不保留旧行、不做列变更，彻底绕开跨库 DDL 差异。

### 4.4 幂等与可重入

迁移代码须幂等：dry-run 不写库；正式运行前校验「`groups` 是否已存在数据」，已迁移则跳过或报错退出，避免重复执行造成 id 漂移。

---

## 5. 渠道选择与缓存适配

### 5.1 内存缓存构建

`model/channel_cache.go` 的 `InitChannelCache` 改造：

- 原来：遍历 `channels`，拆 `channel.Group` 逗号串 × `channel.Models`。
- 改造后：遍历 `channel_groups` 关联表 JOIN `channels`，按 **`group_id` × `models`** 构建 `group2model2channels map[int]map[string][]int`（key 从 group 名变为 `group_id`）。
- 停用分组（`status=disabled`）的渠道不进入缓存。

### 5.2 选渠道入口

- `GetRandomSatisfiedChannel(group_id int, model string, retry int, requestPath string)` ——入参从 group 名改为 `group_id`。
- `model/ability.go` 的 `GetChannel` 及 `getChannelQuery` 同步改为按 `group_id` 查询。
- `requestPath` 过滤（Advanced Custom 渠道）逻辑保持不变。

### 5.3 请求时的数据流

```
请求进入
  └─ middleware 解析身份
        └─ token.group_id（若 > 0 用它，否则 =0）
              └─ =0 → 取 user.group_id（GetUserGroup 改为返回 group_id）
                    └─ user.group_id 仍为 0/停用 → 降级到 default 分组 id（见 §9.3）
                          └─ GetRandomSatisfiedChannel(group_id, model)
                                └─ group2model2channels[group_id][model] → 候选渠道
                                      └─ priority 分层 + weight 加权随机
```

- `GetUserGroup`（`model/user.go:830`）改为返回 `group_id`，Redis 缓存同步调整。
- `token.group_id` 的读取与缓存（如有）同步。

---

## 6. 倍率体系

### 6.1 彻底废弃 GroupRatio map

- 移除 `setting/ratio.go` 中 `GroupRatio`（及 topup 对应 map）作为运行时权威源。
- **`groups.group_ratio` / `topup_ratio` 成为唯一权威源。**
- 迁移时把原 map 每个 entry 写入对应 `groups` 行（§4.2 步骤 3）。

### 6.2 运行时读取

- `GetGroupRatio` / `GetUserGroupRatio` / `GetGroupRatioCopy` 等改为从 `groups` 表读取（带内存/Redis 缓存），替代 map 查询。
- 分组管理页编辑倍率 = `UPDATE groups.group_ratio`，触发缓存刷新。

### 6.3 配置导入/导出

倍率不再以独立 map 形式导入导出，而是随 `groups` 实体整体导入导出（分组名 + 倍率）。历史依赖 `GroupRatio` map 的导入导出入口同步迁移到基于 `groups` 的格式。

---

## 7. API 设计

### 7.1 分组管理 CRUD（新增）

| 方法 | 路径 | 说明 |
|---|---|---|
| `GET` | `/api/group/` | 列表（含 id/name/description/status/ratio/sort） |
| `POST` | `/api/group/` | 新建分组 |
| `PUT` | `/api/group/` | 更新（改名 / 倍率 / 描述 / 排序） |
| `DELETE` | `/api/group/:id` | 软删除（status=disabled）；`default` 分组禁止删除 |

- 改名：`PUT` 时 `name` 变更即触发唯一性校验；成功后所有引用自动跟随（无需扫表）。
- 新建/删除/改名权限：管理员。

### 7.2 用户 / 渠道接口

- `users` / `channels` 接口的 `group` 字段（字符串）→ **`group_id`（int）**。
- **对外 API 硬切 `group_id`**，不接受 group name（用户决策）。调用方需先通过 `GET /api/group/` 获取 id。
- 创建/更新用户、渠道时校验 `group_id` 存在且 `status=enabled`（新建引用不允许指向停用分组）。

### 7.3 规则约束

- 遵循 Rule 1：所有 JSON 序列化走 `common.Marshal` / `common.Unmarshal`。
- 遵循 Rule 6：请求 DTO 中可选字段（如 `description`、`sort`）用指针 + `omitempty`，显式零值能正确传递。

---

## 8. 前端改造

- **新增「分组管理」页**（`web/default/src/features/system-settings/` 下）：列表 + 增删改查 + 改名 + 启停 + 倍率编辑 + 排序。`default` 分组的删除按钮禁用。
- **用户编辑**：`group` 文本输入 → **单选下拉**（数据源 `GET /api/group/`）。
- **渠道编辑**：`group` 逗号串文本输入 → **多选下拉**（数据源同上），提交 `group_id` 数组。
- 倍率可视化编辑器（`group-ratio-visual-editor.tsx`）改为读写 `groups` 实体，而非独立 map。
- i18n：新增分组管理相关文案，走 `bun run i18n:sync`。

---

## 9. 行为规范

### 9.1 改名

- `UPDATE groups.name`；校验 `name` 唯一；`default` 分组**可改名**。
- 改名后所有引用自动跟随；历史日志保留旧名（断开，已接受）。

### 9.2 删除 / 停用

- 删除 = 软删除（`deleted_at` + `status=disabled`）。
- 有引用时也允许（等价于停用），不级联清理引用。
- `default` 分组**禁止删除**（接口层拒绝）。

### 9.3 降级链（解析有效 group_id）

请求解析 `group_id` 时：

1. `token.group_id`（>0 用它）
2. 否则 `user.group_id`（>0 用它）
3. 否则 / 指向已停用分组 → 回退到系统 `default` 分组 id

> 注意：用户/令牌的 `group_id` 不会因分组被停用而自动改写（保留引用），只在**本次请求解析**时降级路由，不写库。

---

## 10. 错误处理

- **迁移失败**：恢复 DB 备份；dry-run 提前暴露唯一名冲突、空名、超大表等问题。
- **改名校验**：`name` 唯一冲突 → 400，提示已存在。
- **删除 `default`**：403/400 拒绝。
- **新建引用指向停用分组**：校验失败，提示选择启用分组。
- **`group_id` 不存在**（脏数据）：选渠道时按降级链回退 default，并 `SysLog` 告警。
- **缓存一致性**：分组改名/启停/删除后刷新 `group2model2channels` 与倍率缓存（沿用现有 `SyncChannelCache` 机制）。

---

## 11. 测试策略（遵循 Rule 9）

测试须保护真实行为与跨模块契约，禁止 reward-hacking 测试；用 `testify/require`（致命断言）+ `assert`（非致命），确定性表驱动。

重点覆盖：

1. **迁移幂等性**：构造含 `default`、多分组逗号串、token 空串、前缀重名（`vip`/`vip2`）的数据 → 迁移后 `group_id` 正确、`channel_groups` 行数正确、`abilities` 重建一致；重复执行不漂移。
2. **改名跟随**：改名后 `users`/`token`/`abilities`/`channel_groups` 路由结果跟随新名；`logs` 历史保留旧名不变。
3. **软删除 / 降级**：停用分组后该分组不再路由；`token.group_id` 指向停用分组时降级到 user 再到 default。
4. **倍率**：`groups.group_ratio` 修改后计费倍率生效；`GroupRatio` map 已彻底移除（编译期保证无残留引用）。
5. **`default` 保护**：删除 default 被拒绝；default 可改名。
6. **缓存重建**：分组变更后 `group2model2channels` 与倍率缓存刷新正确。

---

## 12. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 一次性迁移需维护窗口 | dry-run 预扫 + DB 备份 + 分批回填 + 进度日志；窗口内只读 |
| `abilities` 主键列变更跨库困难 | 用「清空 + 重建」规避 ALTER（§4.3） |
| 大表回填耗时长 | 分批 + 进度日志；维护窗口内执行 |
| `token.group_id=0` 跟随语义漏穿调用链 | §5.3 数据流明确降级链；测试覆盖 |
| 前端用户/渠道编辑改造面广 | 下拉组件复用 `GET /api/group/`；分阶段灰度前端 |
| 历史 `GroupRatio` map 残留引用 | 编译期排查；测试断言无残留 |
| 历史日志按分组统计改名后断开 | 已由用户明确接受（非目标） |

---

## 13. 后续

本设计获批后，进入 `writing-plans` 阶段拆分实现计划（建议按：① 模型与迁移 → ② 缓存与选渠道 → ③ 倍率 → ④ API → ⑤ 前端 → ⑥ 测试 的顺序分阶段）。
