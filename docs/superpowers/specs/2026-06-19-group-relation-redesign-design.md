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
| `logs` / `tasks` / `perf_metric` | `group` | 历史/快照，记录「当时」的分组名 |
| `subscription_plans` / `user_subscriptions` | `upgrade_group` / `downgrade_group` / `prev_user_group` | 订阅升级 / 降级的活跃配置与快照混合字段 |

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
- **历史表 ID 化**：`logs` / `tasks` / `perf_metric` 的 `group` 字符串**保持不动**，作为历史快照保留旧名（用户决策）。订阅表不在此非目标内，因其包含活跃升级 / 降级引用，需按 §3.2 ID 化。
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
| 对外 API 入参 | **活跃引用硬切 ID**：单分组用 `group_id`，渠道多分组用 `group_ids`；不接受 group name |
| Token 分组模式 | `token.group_mode` 明确表达 `inherit` / `fixed` / `auto`，避免把 `0` 同时当作跟随和自动 |
| `default` 分组 | 可改名、不可删；用 `groups.is_default` 作为稳定系统标识，不再依赖名称 |
| 分组配置存储 | **分组相关配置全部 ID 化**：基础倍率入 `groups`；分组间倍率、可用分组、自动分组、分组限流均迁移到 ID 语义 |

---

## 3. 目标数据模型

### 3.1 新增 `groups` 实体表

```go
type Group struct {
    Id          int            `json:"id" gorm:"primaryKey"`
    Name        string         `json:"name" gorm:"type:varchar(64);uniqueIndex"`
    Description string         `json:"description" gorm:"type:varchar(255)"`
    Status      int            `json:"status" gorm:"default:1"`   // 1=enabled, 2=disabled，对齐 common.ChannelStatus
    IsDefault   bool           `json:"is_default" gorm:"default:false;index"`
    UserSelectable bool        `json:"user_selectable" gorm:"default:false"`
    AutoSelectable bool        `json:"auto_selectable" gorm:"default:false;index"`
    GroupRatio  float64        `json:"group_ratio" gorm:"default:1"`
    TopUpRatio  float64        `json:"topup_ratio" gorm:"default:1"`
    RateLimitTotal   *int      `json:"rate_limit_total,omitempty" gorm:"type:int"`
    RateLimitSuccess *int      `json:"rate_limit_success,omitempty" gorm:"type:int"`
    Sort        int            `json:"sort" gorm:"default:0"`
    CreatedTime int64          `json:"created_time" gorm:"bigint"`
    UpdatedTime int64          `json:"updated_time" gorm:"bigint"`
    DeletedAt   gorm.DeletedAt `json:"-" gorm:"index"`            // 软删除
}
```

- `name` 唯一索引；改名只 `UPDATE name`。
- `status`：`enabled` 时参与路由；`disabled`（软删除）后不再路由，但引用保留。
- `is_default`：系统默认分组的稳定标识。名称可改，但 `is_default=true` 的行不可删除、不可停用。
- `user_selectable` / `auto_selectable` / `sort`：替代旧 `UserUsableGroups` 与 `AutoGroups` 的基础配置。
- `group_ratio` / `topup_ratio` / `rate_limit_*`：基础倍率和分组级模型请求限流的权威源（见 §6）。

### 3.2 A 类活跃引用表（字符串 → ID）

| 表 | 变更 |
|---|---|
| `users` | `group varchar` → **`group_id int`**（index；迁移时回填，新建用户由代码赋 `default` 分组 id，不依赖 DB 动态默认值） |
| `token` | `group varchar` → **`group_mode varchar(16)` + `group_id int`**。`group_mode=inherit` 表示跟随用户；`fixed` 表示使用 `group_id`；`auto` 表示保留现有自动分组 / 跨分组重试语义 |
| `abilities` | `group varchar`（主键成员）→ **`group_id int`**（主键成员）；主键变为 `(group_id, model, channel_id)` |
| `subscription_plans` | `upgrade_group` / `downgrade_group` → **`upgrade_group_id` / `downgrade_group_id`**（`0` 表示不变 / 使用默认回退语义，见 §6.4） |
| `user_subscriptions` | `upgrade_group` / `downgrade_group` → **`upgrade_group_id` / `downgrade_group_id`**；`prev_user_group` 保留为名称快照，同时新增 **`prev_user_group_id`** 供降级写回 |

### 3.3 渠道多分组：新增 `channel_groups` 关联表

```go
type ChannelGroup struct {
    ChannelId int `json:"channel_id" gorm:"primaryKey;autoIncrement:false"`
    GroupId   int `json:"group_id" gorm:"primaryKey;autoIncrement:false;index"`
}
```

- 复合主键 `(channel_id, group_id)`；`group_id` 加索引以支持「按分组反查渠道」。
- `channels.group` 逗号串列**移除**，多分组改由本表表达。

### 3.4 分组关系配置表

旧版分组配置大量以 group name 作为 map key。为保证改名后配置自动跟随，活跃配置统一改为 ID 语义：

```go
type GroupUsableGroup struct {
    UserGroupId  int    `json:"user_group_id" gorm:"primaryKey;autoIncrement:false"`
    UsingGroupId int    `json:"using_group_id" gorm:"primaryKey;autoIncrement:false"`
    Description  string `json:"description" gorm:"type:varchar(255)"`
    Enabled      bool   `json:"enabled" gorm:"default:true"`
}

type GroupGroupRatio struct {
    UserGroupId  int     `json:"user_group_id" gorm:"primaryKey;autoIncrement:false"`
    UsingGroupId int     `json:"using_group_id" gorm:"primaryKey;autoIncrement:false"`
    Ratio        float64 `json:"ratio" gorm:"default:1"`
}
```

- `GroupUsableGroup` 替代 `UserUsableGroups` 与 `group_special_usable_group` 的最终结果；基础可用分组由 `groups.user_selectable` 表达，特殊加减项迁移成显式 allow/deny 后的最终关系。
- `GroupGroupRatio` 替代旧 `GroupGroupRatio` map，表达「用户所在分组使用某个 token/路由分组时的特殊倍率」。
- `groups.auto_selectable` + `sort` 替代 `AutoGroups` 列表。自动分组候选仍需同时满足用户可用关系。
- `groups.rate_limit_total` / `rate_limit_success` 替代 `ModelRequestRateLimitGroup` 中按分组名配置的限流覆盖。

### 3.5 历史表与展示快照（保留名称）

`logs` / `tasks` / `perf_metric` 的 `group varchar` 列**完全保留**，不回填、不 ID 化。运行时虽然按 `group_id` 路由和计费，但写入日志、任务、性能统计时仍解析出当时的 `group_name` 快照，继续写入这些历史列。按分组统计消费时，改名前后的历史数据会「断开」——这是用户明确接受的取舍。

订阅相关表不再整体归为历史表：

- `subscription_plans` 是活跃配置，目标分组必须 ID 化。
- `user_subscriptions` 同时包含活跃降级逻辑与历史展示。降级执行使用 `*_group_id`；列表和审计展示可保留 `prev_user_group` 名称快照。

### 3.6 关键不变量

- **改名**：`UPDATE groups.name` 一行 → `users` / `token fixed` / `subscription_plans` / `user_subscriptions` / `abilities` / `channel_groups` / 分组关系配置全部自动跟随（都引用 id）——**核心目标达成**。
- **删除 / 停用**：`status=disabled` + `deleted_at`（软删除），引用保留不丢；停用分组不参与路由。
- **abilities 重建**：从 `channel_groups × channels.models` 笛卡尔积派生（替换原来拆分 `channel.group` 逗号串的逻辑）。
- **`default` 分组**：迁移时由字符串 `'default'` 映射而来，并标记 `is_default=true`；可改名、不可删、不可停用。
- **`auto` token**：不是普通分组，不进入 `groups` 表；由 `token.group_mode='auto'` 表示，继续走自动分组候选与跨分组重试逻辑。

> 关于 SQL 保留字：旧列与历史表的 `group` 列仍是保留字，查询沿用 `commonGroupCol` / `commonKeyCol`（`model/main.go`）；新增的 `group_id` 非保留字，反而规避了保留字问题。

---

## 4. 数据迁移（一次性迁移）

### 4.1 前置条件与维护窗口

- 迁移期间进入**维护模式**（拒绝写请求或短暂停服）。
- 迁移前**强制要求 DB 备份**；提供 **dry-run** 预扫描，先列出将创建的唯一分组名清单供人工确认。
- 大表（`users` / `abilities`）回填分批进行，输出进度日志。
- 失败处理：迁移事务失败 → 恢复备份。

### 4.2 9 个原子步骤

1. **建表 / 增列**：`groups`、`channel_groups`、`group_usable_groups`、`group_group_ratios`；给 `users` 增 `group_id`，给 `token` 增 `group_mode` / `group_id`，给订阅相关表增 `*_group_id`（遵循 `model/main.go` 的 `ADD COLUMN` 模式，兼容三种 DB；遵循 Rule 2）。`abilities` **不增列**——走步骤 7 的清空重建。
2. **扫描唯一分组名**：从 `users.group`、`channels.group`（拆逗号）、`token.group`（排除空串与特殊值 `auto`）、`abilities.group`、订阅计划 / 用户订阅的升级降级字段，以及旧分组配置 map 的 key/value 汇总去重。
3. **upsert `groups`**：为每个唯一名建实体；`group_ratio` / `topup_ratio` 取自当前 `GroupRatio` / `TopupGroupRatio` map；`ModelRequestRateLimitGroup` 写入 `rate_limit_*`；`UserUsableGroups` 写入 `user_selectable` 与描述；`AutoGroups` 写入 `auto_selectable` 与排序；`'default'` 映射行标记 `is_default=true`、`status=enabled`。
4. **迁移分组关系配置**：
   - `GroupGroupRatio` map → `group_group_ratios(user_group_id, using_group_id, ratio)`。
   - `UserUsableGroups` 与 `group_special_usable_group` → 对每个用户分组计算最终可用集合，写入 `group_usable_groups`。旧 `-:` 移除项不单独保存为 deny 规则，迁移结果以显式最终关系为准。
5. **回填活跃引用**：
   - `users.group_id` = `groups.id where name = users.group`；空值归到 `is_default=true` 的分组。
   - `token.group_mode/group_id`：原 `group=''` → `inherit, 0`；原 `group='auto'` → `auto, 0`；其他非空 → `fixed, 对应 id`。
   - `subscription_plans.upgrade_group_id/downgrade_group_id`：空串 → `0`；非空 → 对应 id。
   - `user_subscriptions.upgrade_group_id/downgrade_group_id/prev_user_group_id`：空串 → `0`；非空 → 对应 id，同时保留原 `prev_user_group` 名称快照用于展示。
   - （`abilities` 的 `group_id` 在步骤 7 重建时生成，不在此回填。）
6. **建 `channel_groups`**：拆 `channels.group` 逗号串 → 插入 `(channel_id, group_id)`；空项、重复项、首尾空格在迁移预扫描阶段报告并按规范化结果写入。
7. **重建 `abilities`**（关键简化，见 §4.3）：清空后从 `channel_groups × channels.models` 重新派生，主键直接以 `group_id` 建表——**规避主键列 `varchar→int` 的跨库变更难题**。
8. **一致性校验**：抽样校验用户、token、渠道、订阅和分组配置的迁移结果；运行能力表重建校验，确保每个旧 `(group, model, channel_id)` 都能映射到新 `(group_id, model, channel_id)`，且 `enabled/priority/weight/tag` 行为等价。
9. **切换并清理**：代码读路径切到 ID；删除 `users.group` / `token.group` / `abilities.group`(旧) / `channels.group` 等旧字符串列；旧 `GroupRatio`、`TopupGroupRatio`、`GroupGroupRatio`、`UserUsableGroups`、`AutoGroups`、`ModelRequestRateLimitGroup` 配置入口改为只读兼容或下线。恢复服务。

### 4.3 abilities 重建而非 ALTER

`abilities` 的 `group` 既是主键成员又要改类型（`varchar→int`），三库都无法用简单 `ALTER` 改主键。`abilities` 可重建，但不是只含主键的空派生表：它还承载 `enabled`、`priority`、`weight`、`tag` 等渠道选择行为字段。因此迁移策略是：

> 维护窗口内读取旧 `abilities` 行快照 → `TRUNCATE abilities` → 用新结构（`group_id` 主键）建表 → 从 `channel_groups × channels.models` 重新生成全部记录。

重建时字段来源必须保持等价：

- `model` / `channel_id` / `group_id` 来自 `channels.models × channel_groups`。
- `enabled` 继续由渠道状态与原能力状态的语义决定。若旧表中存在按 tag 或修复工具导致的能力级禁用状态，迁移必须先读取旧 `(group, model, channel_id)` 行并映射到新主键，优先保留旧 `enabled`。
- `priority` / `weight` / `tag` 优先保留旧 ability 行；缺失时才回退到 `channels.priority` / `channels.weight` / `channels.tag`。

这样仍避免跨库 DDL 差异，但不会丢失现有能力表上的运行时选择参数。

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
        └─ 解析 token.group_mode
              ├─ inherit → 使用 user.group_id
              ├─ fixed   → 使用 token.group_id
              └─ auto    → 根据 user.group_id 的可用分组 + auto_selectable 排序逐组尝试
                    └─ 候选 group_id 无效/停用 → 按降级链处理（见 §9.3）
                          └─ GetRandomSatisfiedChannel(group_id, model)
                                └─ group2model2channels[group_id][model] → 候选渠道
                                      └─ priority 分层 + weight 加权随机
```

- `GetUserGroup`（`model/user.go:830`）拆成两类接口：路由用 `GetUserGroupID` 返回 `group_id`；展示/日志用 `GetGroupNameByID` 或带缓存的 `GroupRef` 返回 `id + name`。
- `token.group_mode` / `token.group_id` 的读取与缓存（如有）同步。
- `RelayInfo` / gin context 同时保存 `UsingGroupID`、`UsingGroupName`、`UserGroupID`、`UserGroupName`、`TokenGroupMode`。路由、权限、倍率用 ID；日志、错误信息、任务快照继续写名称。
- `auto` 跨分组重试继续保留 `ContextKeyAutoGroupIndex` / `ContextKeyAutoGroupRetryIndex` 语义，但保存的当前候选应是 `group_id`；展示时再解析名称。

---

## 6. 分组配置与倍率体系

### 6.1 彻底废弃按名称为 key 的分组配置

- 移除 `setting/ratio.go` 中 `GroupRatio`（及 topup 对应 map）作为运行时权威源。
- 移除或兼容下线这些旧配置入口作为运行时权威源：`TopupGroupRatio`、`GroupGroupRatio`、`UserUsableGroups`、`group_ratio_setting.group_special_usable_group`、`AutoGroups`、`ModelRequestRateLimitGroup`。
- **`groups`、`group_usable_groups`、`group_group_ratios` 成为唯一权威源。**
- 迁移时把原 map / list 每个 entry 写入对应实体或关系表（§4.2 步骤 3-4）。

### 6.2 运行时读取

- `GetGroupRatio(groupID)` / `GetTopupGroupRatio(groupID)` 从 `groups` 表或分组缓存读取。
- `GetUserGroupRatio(userGroupID, usingGroupID)` 先查 `group_group_ratios`，没有特殊项再查 `groups.group_ratio`。
- `GetUserUsableGroups(userGroupID)` 从 `group_usable_groups` + `groups.user_selectable` 构建，过滤 disabled / soft-deleted 分组。
- `GetUserAutoGroups(userGroupID)` 从可用分组中过滤 `auto_selectable=true`，按 `sort, id` 排序。
- `GetGroupRateLimit(groupID)` 从 `groups.rate_limit_total/rate_limit_success` 读取；为空则使用全局限流默认值。
- 分组管理页编辑倍率、可选性、自动分组选项和限流 = 更新对应表，触发统一分组配置缓存刷新。

### 6.3 配置导入/导出

分组配置不再以独立 JSON map 形式导入导出，而是随 `groups` 与分组关系整体导入导出：

- `groups`：名称、描述、状态、`is_default`、倍率、充值倍率、用户可选、自动可选、限流、排序。
- `group_usable_groups`：用户分组 ID / 使用分组 ID / 描述。
- `group_group_ratios`：用户分组 ID / 使用分组 ID / 特殊倍率。

为便于人工迁移，导出格式可以同时包含名称和 ID；导入时以 ID 优先、名称作为同实例内的匹配辅助，但运行时权威仍是 ID。

### 6.4 订阅升级 / 降级

订阅计划的 `upgrade_group_id` / `downgrade_group_id` 是活跃引用：

- 创建 / 更新订阅计划时校验目标分组存在且 enabled；`0` 表示不改变用户分组或使用默认回退语义。
- 创建用户订阅时，把计划中的目标 ID 快照到 `user_subscriptions`，并记录 `prev_user_group_id` 与 `prev_user_group` 名称快照。
- 订阅过期 / 取消时按 ID 写回 `users.group_id`；展示和审计仍可显示创建时保存的名称快照。
- 如果目标分组已停用，过期 / 取消时按 §9.3 降级链回退到 `is_default=true` 的分组，并写 `SysLog` 告警。

---

## 7. API 设计

### 7.1 分组管理 CRUD（新增）

| 方法 | 路径 | 说明 |
|---|---|---|
| `GET` | `/api/group/` | 列表（含 id/name/description/status/is_default/ratio/topup_ratio/selectable/rate_limit/sort） |
| `POST` | `/api/group/` | 新建分组 |
| `PUT` | `/api/group/` | 更新（改名 / 倍率 / 描述 / 排序） |
| `DELETE` | `/api/group/:id` | 软删除（status=disabled）；`is_default=true` 分组禁止删除 |

- 改名：`PUT` 时 `name` 变更即触发唯一性校验；成功后所有引用自动跟随（无需扫表）。
- 新建/删除/改名权限：管理员。
- `is_default=true` 的分组禁止删除和停用；名称允许修改。
- 列表响应同时返回 ID 与名称，供前端展示和外部调用方选择。

### 7.2 用户 / 渠道接口

- `users` 接口的 `group` 字段（字符串）→ **`group_id`（int）**。
- `channels` 接口的 `group` 逗号串字段 → **`group_ids`（int 数组）**。
- Token 接口的 `group` 字段改为 **`group_mode` + `group_id`**：
  - `inherit`：`group_id` 必须为 `0` 或省略；
  - `fixed`：`group_id` 必须存在且指向 enabled 分组；
  - `auto`：`group_id` 必须为 `0` 或省略，保留自动分组 / 跨分组重试。
- **活跃引用对外 API 硬切 ID**，不接受 group name（用户决策）。调用方需先通过 `GET /api/group/` 获取 id。
- 创建/更新用户、渠道、token fixed 分组和订阅目标分组时校验对应 `group_id` / `group_ids` 存在且 `status=enabled`（新建引用不允许指向停用分组）。

### 7.3 兼容保留的名称字段

- 日志、任务、性能统计、用量详情等历史 / 展示接口继续返回 `group` 名称快照。
- 错误消息可使用当前解析到的 `group_name`，但业务判断不得再按名称比较。
- Playground 请求里的临时分组选择改为 `group_id`；旧 `group` 字段如需兼容，只能作为短期只读迁移入口，并必须在文档和响应中标记 deprecated。

### 7.4 规则约束

- 遵循 Rule 1：所有 JSON 序列化走 `common.Marshal` / `common.Unmarshal`。
- 遵循 Rule 6：请求 DTO 中可选字段（如 `description`、`sort`）用指针 + `omitempty`，显式零值能正确传递。

---

## 8. 前端改造

- **新增「分组管理」页**（`web/src/features/system-settings/` 下）：列表 + 增删改查 + 改名 + 启停 + 倍率编辑 + 排序。`is_default=true` 分组的删除 / 停用按钮禁用。
- **用户编辑**：`group` 文本输入 → **单选下拉**（数据源 `GET /api/group/`）。
- **渠道编辑**：`group` 逗号串文本输入 → **多选下拉**（数据源同上），提交 `group_ids` 数组。
- **Token 编辑**：新增模式选择（跟随用户 / 固定分组 / 自动分组）；固定分组时显示单选分组下拉，自动分组时显示跨分组重试设置。
- **订阅计划编辑**：升级 / 降级分组改为 ID 下拉；空值表示不改变或回退到购买前分组。
- 倍率可视化编辑器（`group-ratio-visual-editor.tsx`）改为读写 `groups`、`group_usable_groups`、`group_group_ratios`，不再提交旧 JSON map。
- 分组限流编辑器改为读写 `groups.rate_limit_total/rate_limit_success`。
- i18n：新增分组管理相关文案，走 `bun run i18n:sync`。

---

## 9. 行为规范

### 9.1 改名

- `UPDATE groups.name`；校验 `name` 唯一；`default` 分组**可改名**。
- 改名后所有 ID 引用自动跟随；历史日志 / 任务 / 性能统计保留旧名（断开，已接受）。
- `is_default` 不随名称变化；删除和回退判断始终按 `is_default=true` 的行。

### 9.2 删除 / 停用

- 删除 = 软删除（`deleted_at` + `status=disabled`）。
- 有引用时也允许（等价于停用），不级联清理引用。
- `is_default=true` 的分组**禁止删除和停用**（接口层拒绝）。

### 9.3 降级链（解析有效 group_id）

请求解析有效 `group_id` 时：

1. `token.group_mode=fixed` 且 `token.group_id>0` → 使用 token 分组。
2. `token.group_mode=auto` → 在用户可用且 `auto_selectable=true` 的分组中按排序逐个尝试；每个候选都必须 enabled。
3. `token.group_mode=inherit` 或 fixed 无效 → 使用 `user.group_id`。
4. 候选不存在、为 0、已停用或已软删 → 回退到 `is_default=true` 的系统分组 id。

> 注意：用户/令牌的 `group_id` 不会因分组被停用而自动改写（保留引用），只在**本次请求解析**时降级路由，不写库。

---

## 10. 错误处理

- **迁移失败**：恢复 DB 备份；dry-run 提前暴露唯一名冲突、空名、超大表等问题。
- **改名校验**：`name` 唯一冲突 → 400，提示已存在。
- **删除 / 停用默认分组**：`is_default=true` → 403/400 拒绝。
- **新建引用指向停用分组**：校验失败，提示选择启用分组。
- **Token 模式非法**：`fixed` 缺少有效 `group_id`、`inherit/auto` 携带非零 `group_id`、未知 `group_mode` → 400。
- **订阅目标分组停用**：创建 / 更新计划时拒绝；过期 / 取消执行时如果历史目标已停用，回退默认分组并 `SysLog` 告警。
- **`group_id` 不存在**（脏数据）：选渠道时按降级链回退 default，并 `SysLog` 告警。
- **缓存一致性**：分组改名/启停/删除后刷新 `group2model2channels`、分组名称缓存、分组配置缓存、倍率缓存与限流缓存（沿用现有 `SyncChannelCache` 机制并补充分组配置刷新入口）。

---

## 11. 测试策略（遵循 Rule 9）

测试须保护真实行为与跨模块契约，禁止 reward-hacking 测试；用 `testify/require`（致命断言）+ `assert`（非致命），确定性表驱动。

重点覆盖：

1. **迁移幂等性**：构造含 `default`、多分组逗号串、token 空串 / `auto` / 固定分组、前缀重名（`vip`/`vip2`）、订阅升级降级、旧分组配置 map 的数据 → 迁移后 `group_id`、`group_mode`、关系表、`channel_groups` 行数正确；重复执行不漂移。
2. **abilities 重建保真**：旧能力行包含自定义 `enabled/priority/weight/tag` 时，迁移后新 `(group_id, model, channel_id)` 保留等价行为；缺失旧行时才从 channel 默认值生成。
3. **改名跟随**：改名后 `users`/`token fixed`/`subscription_plans`/`user_subscriptions`/`abilities`/`channel_groups`/分组配置关系的路由和计费结果跟随新名；`logs` / `tasks` / `perf_metric` 历史保留旧名不变。
4. **Token 模式**：`inherit` 跟随用户；`fixed` 使用 token 分组；`auto` 按用户可用自动分组与跨分组重试选择渠道；非法组合被拒绝。
5. **软删除 / 降级**：停用普通分组后该分组不再路由；fixed token 指向停用分组时降级到 user 再到 default；订阅过期目标停用时降级 default。
6. **倍率与配置**：`groups.group_ratio/topup_ratio`、`group_group_ratios`、`group_usable_groups`、`auto_selectable`、`rate_limit_*` 修改后运行时生效；旧 map 不再作为权威源（编译期和行为测试保证无残留运行时依赖）。
7. **`default` 保护**：`is_default=true` 分组删除 / 停用被拒绝；default 可改名；回退逻辑不依赖名称。
8. **缓存重建**：分组变更后 `group2model2channels`、名称缓存、可用分组 / 自动分组缓存、倍率缓存和限流缓存刷新正确。

---

## 12. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 一次性迁移需维护窗口 | dry-run 预扫 + DB 备份 + 分批回填 + 进度日志；窗口内只读 |
| `abilities` 主键列变更跨库困难 | 用「读取旧行快照 + 清空 + 保真重建」规避 ALTER（§4.3） |
| 大表回填耗时长 | 分批 + 进度日志；维护窗口内执行 |
| `auto` token 语义在 ID 化后丢失 | `group_mode` 显式建模 `inherit/fixed/auto`；测试覆盖自动分组和跨分组重试 |
| 订阅升级 / 降级仍按旧分组名写用户表 | 订阅计划和用户订阅目标分组 ID 化；保留名称仅作展示快照 |
| 分组配置 map 改名后断链 | 旧 map 迁移为 `groups` 与关系表；运行时只按 ID 查询 |
| 前端用户/渠道编辑改造面广 | 下拉组件复用 `GET /api/group/`；分阶段灰度前端 |
| 历史分组配置 map 残留引用 | 编译期排查；测试断言无残留运行时权威源 |
| 历史日志按分组统计改名后断开 | 已由用户明确接受（非目标） |

---

## 13. 后续

本设计获批后，进入 `writing-plans` 阶段拆分实现计划（建议按：① 模型与迁移 → ② 缓存与选渠道 → ③ 倍率 → ④ API → ⑤ 前端 → ⑥ 测试 的顺序分阶段）。
