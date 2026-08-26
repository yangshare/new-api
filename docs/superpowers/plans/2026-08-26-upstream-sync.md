# 上游全覆盖同步 + 个性化清单重放 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 按《上游同步设计》落地本轮同步——产出单一事实源手册 `docs/upstream-sync.md`，并用它完成 upstream/main 83 个 commit 的全量覆盖合并 + 本地个性化逐项重放 + 机械校验。

**架构：** 手册先行（A/B/C 三类清单 + 五步流程 + 验证门槛），随后在同一会话内按手册执行同步：备份分支 → `--no-commit` 合并并对全部"双方都改"文件整文件取上游 → 按 B 类清单逐项重放 → 锚点校验 → 漂移检测归因 → 六道验证门槛 → 分批提交。

**技术栈：** git（no-commit merge + 整文件 checkout）、Go 1.22 / GORM（model/setting/service）、Bun + Rsbuild + TypeScript + vitest（web）、PowerShell（本机 shell，所有命令均为 PS 语法）。

---

## 执行环境须知（每个任务开始前通读）

1. **Shell 一律用 PowerShell 工具**，Windows 原生路径（如 `E:\开源项目\new-api\web`）。工作目录 = 仓库根 `E:\开源项目\new-api`。
2. 分支固定为 `dev`，本任务群**不建 worktree**（备份分支即回滚手段）。远端已配好：`origin=yangshare/new-api`，`upstream=QuantumNous/new-api`。
3. 每步执行前检查 `git status --porcelain` 应无未预期残留；预期产物除外。
4. 所有 commit message 末尾追加：
   ```
   Co-Authored-By: Claude <noreply@anthropic.com>
   ```
5. **保护信息红线**：nеw-аρi / QuаntumΝоuѕ 相关品牌、许可头、README 引用一律不得改动。前端禁跑 `bun run format` / `format --write`（历史上有误改 CLAUDE.md 的先例），只允许只读的 `format:check`。
6. Go 文件改动后统一 `gofmt -w <file>` 再提交。

## 考古结论速览（2026-08-26 快照，计划的事实基线）

- merge-base = `bc14c18f6024e79cba1c08d02cd007796e12d668`；upstream 领先 **83 commits**，dev 领先 79 commits。最新本地 tag 为 `v1.3.1-dockeronly`。
- **双方都改文件 = 30 个**（见下表）。其中 `relaykit` 模块抽取（368 文件）、int32 弃用等上游大动作与本地个性化几乎不重叠。
- **规格修正 ①（重要）：** 设计文档 B4 所述"嵌套计费（GroupGroupRatio/baseRatioByName）需重放"经核实**不成立**——这组符号在 merge-base 双方共享、`group-ratio-visual-editor.tsx` 等载体文件本次仅上游单方修改，自动并入即可。本地真正需要重放的是这些文件里的 **silent-batch 更新特性**（B4 新定义）与 **unset-models 页签剔除**（C1）。
- **规格修正 ②：** 初始 B 清单只有 8 项，完整考古扩到 **B1–B11**（新增：uuid 测试化 B9、eslint/lint 抑制注释组 B10、i18n 六键 B11、flow.test 遮蔽用例并入 B3 任务、subscription 同步 i18n 并入 B11）。
- 三个"分叉演化"大差异文件定性完毕：`flow.test.ts`（上游迁 vitest，取上游版并以 vitest 语法重放遮蔽用例）、`fetch-models-dialog.tsx` 与 `routing-reliability-section.tsx`（取上游重构版，仅重放被验证过的少量本地小改）。

**双方都改 30 文件（本轮覆盖对象，当次必须现算复核）：**

```
.github/workflows/electron-build.yml          web/src/features/channels/components/dialogs/fetch-models-dialog.tsx
.github/workflows/release.yml                 web/src/features/dashboard/lib/flow.test.ts
.gitignore                                    web/src/features/models/components/drawers/model-mutate-drawer.tsx
Dockerfile                                    web/src/features/profile/components/tabs/account-bindings-tab.tsx
model/subscription.go                         web/src/features/system-settings/auth/oauth-section.tsx
service/channel_affinity_usage_cache_test.go  web/src/features/system-settings/billing/section-registry.tsx
setting/ratio_setting/model_ratio.go          web/src/features/system-settings/hooks/use-update-option.ts
web/src/features/auth/sign-in/components/user-auth-form.tsx
web/src/features/system-settings/models/ratio-settings-card.tsx
web/src/features/system-settings/models/routing-reliability-section.tsx
web/src/features/system-settings/types.ts
web/src/features/usage-logs/components/dialogs/details-dialog.tsx
web/src/features/usage-logs/lib/format.ts
web/src/features/users/components/dialogs/user-binding-dialog.tsx
web/src/features/wallet/hooks/use-billing-history.ts
web/src/i18n/locales/{en,zh,zh-TW,fr,ru,ja,vi}.json
```

## 文件结构

| 操作 | 文件 | 职责 |
|---|---|---|
| 创建 | `docs/upstream-sync.md` | 同步手册：五步流程、验证门槛、A/B/C 三类清单、锚点索引（单一事实源） |
| 覆盖+重放 | 上表 30 文件 | 整文件取上游版后按 B 条目重放本地内容 |
| 自动并入 | `relaykit`/int64 迁移等纯上游新增文件 | 无需人工干预，merge/checkout 自带 |

重放辅助事实（不必创建新代码文件）：
- silent-batch 特性的判定函数位于本地独有文件 `web/src/features/system-settings/lib/update-option-results.ts`（A 类，merge 天然保留，直接 import 即可）。
- 多键索引测试 `web/src/features/usage-logs/lib/format-multikey.test.ts` 为 A 类本地独有，保留不动。
- 合并后 web 依赖里会出现 `vitest`（上游 `test: vitest run` 进入 `web/package.json`），所以合并后第一步是 `bun install`。

---

## 任务 1：手册骨架（头部 + 使用规则 + 五步流程 + 验证门槛）

**文件：**
- 创建：`docs/upstream-sync.md`

- [ ] **步骤 1：写入手册骨架全文**

用 Write 工具创建 `docs/upstream-sync.md`，内容**一字不改**使用以下文本：

````markdown
# 上游同步手册（QuantumNous/new-api fork）

> 单一事实源：每次同步前读本手册、同步中按本手册执行、同步后把当次考古结论补录回本手册。
> 配套设计文档：`docs/superpowers/specs/2026-08-26-upstream-sync-design.md`

## 核心模式

基底跟随上游 + 个性化清单重放：对所有"双方都改"的上游文件**整文件取上游版**（不信任何自动合并），再按 B 类清单把个性化逐项重放回去，最后用锚点 grep + 漂移 diff 机械确认无遗漏。

## 五步同步流程（每轮固定执行）

1. **备份**：工作区必须干净（`git status --porcelain` 为空），`git branch dev-backup-pre-sync`（若已存在上一轮残留分支：`git branch -D dev-backup-pre-sync` 后重建）。
2. **合并与全覆盖**：
   ```powershell
   git fetch upstream
   $mb = git merge-base dev upstream/main
   $localChanged  = git diff --name-only $mb dev
   $upstreamChanged = git diff --name-only $mb upstream/main
   $both = @($localChanged | Where-Object { $upstreamChanged -contains $_ })
   $both.Count    # 当次现算！不要照抄历史清单
   foreach ($f in $both) { git checkout upstream/main -- $f }
   ```
   - 若出现不在 `$both` 内的未解决冲突路径：停下来，把该文件同样整文件取上游并把发现记录进 B/C 清单后再继续（正常情况不应发生）。
   - 随后提交 merge commit（message 例：`merge(upstream): 全量覆盖同步 upstream/main (<N> commits, merge-base <short>)`）。
3. **重放**：按 B 类清单逐项把个性化改回；与上游新逻辑交织的手工融合（典型：B8）。
4. **锚点校验**：按文末锚点索引逐项 grep，任一失败回到第 3 步补做。
5. **漂移检测**：见下节脚本；清单外差异必须归因为「上游变更」或「清单某项」，否则补录清单或明确记入 C 类放弃。

## 验证门槛（第 5 步之后、每轮收尾 commit 之前，按序全过）

1. `go build ./...`（退出码 0）
2. `go test ./common/... ./pkg/billingexpr/... ./relay/common/... ./setting/ratio_setting/... ./relay/channel/ai360/... ./service/ -run "TestObserveChannelAffinityUsageCache"`（压计费与本地适配层）
3. `go test ./model/ -run Subscription`（订阅链路）
4. web 目录：`bun install`（上游可能新增依赖）→ `bun run typecheck` → `bun run build`
5. `bun run format:check`（**只读**；禁止 `format --write`）。若失败：只对手工修复受影响行，不允许全局写回。
6. 保护文件核对（两条都应输出空 diff）：
   ```powershell
   git diff dev-backup-pre-sync -- CLAUDE.md web/src/styles/theme.css
   ```
   注意 CLAUDE.md 在本轮以后若进入双方都改集合，重放项 B6 生效后此 diff 只允许等于 B6 内容。

## 漂移检测脚本（第 5 步直接粘贴运行）

```powershell
$backup = 'dev-backup-pre-sync'
$mb = git merge-base $backup upstream/main
$changed      = @(git diff --name-only "$backup..dev")
$both         = @(git diff --name-only "$mb..$backup" | Where-Object { (git diff --name-only "$mb..upstream/main") -contains $_ })
# 1) 重放过但不含任何 B 项的覆盖文件：最终态必须与 upstream/main 完全一致
#    （含 B 项的文件在下面 $replayFiles 里列出，豁免该断言）
$replayFiles = @(
  'setting/ratio_setting/model_ratio.go'
  'model/subscription.go'
  'service/channel_affinity_usage_cache_test.go'
  '.github/workflows/electron-build.yml'; '.github/workflows/release.yml'; '.gitignore'; 'Dockerfile'
  'web/src/i18n/locales/en.json'; 'web/src/i18n/locales/fr.json'; 'web/src/i18n/locales/ja.json'
  'web/src/i18n/locales/ru.json'; 'web/src/i18n/locales/vi.json'; 'web/src/i18n/locales/zh-TW.json'; 'web/src/i18n/locales/zh.json'
  'web/src/features/auth/sign-in/components/user-auth-form.tsx'
  'web/src/features/channels/components/dialogs/balance-query-dialog.tsx'
  'web/src/features/channels/components/dialogs/fetch-models-dialog.tsx'
  'web/src/features/dashboard/lib/flow.test.ts'
  'web/src/features/models/components/drawers/model-mutate-drawer.tsx'
  'web/src/features/profile/components/tabs/account-bindings-tab.tsx'
  'web/src/features/system-settings/auth/oauth-section.tsx'
  'web/src/features/system-settings/billing/section-registry.tsx'
  'web/src/features/system-settings/hooks/use-update-option.ts'
  'web/src/features/system-settings/models/ratio-settings-card.tsx'
  'web/src/features/system-settings/models/routing-reliability-section.tsx'
  'web/src/features/system-settings/types.ts'
  'web/src/features/usage-logs/components/dialogs/details-dialog.tsx'
  'web/src/features/usage-logs/lib/format.ts'
  'web/src/features/users/components/dialogs/user-binding-dialog.tsx'
  'web/src/features/wallet/hooks/use-billing-history.ts'
)
foreach ($f in $both) {
  if ($replayFiles -notcontains $f) {
    $r = git diff --stat upstream/main -- $f
    if ($r) { "FAIL 不含B项却与上游不同`t$f" }
  }
}
# 2) 本地单方修改的文件（上游未动）：备份以来不许有任何变化
$oursOnly = @(git diff --name-only "$mb..$backup" | Where-Object { (git diff --name-only "$mb..upstream/main") -notcontains $_ })
foreach ($f in $oursOnly) {
  if (-not (git diff --quiet "$backup..dev" -- $f)) { "FAIL 仅本地文件被动了`t$f" }
}
"漂移检测结束。没有 FAIL 行即通过。"
```

## A 类：本地独有文件（上游无对应文件，merge 天然保留）

盘点目的：防误删、让新会话快速了解本地特性面。按目录分组（较完整枚举，散件忽略）：

| 组 | 内容 |
|---|---|
| relay 适配 | `relay/channel/ai360/`（360AI 渠道适配 + 敏感数据遮蔽，注意上游历史里也有同名目录，属共享基底，本地在其上叠了一个 feature commit） |
| 订阅特性后端 | `model/subscription_sync_test.go`；`controller/subscription.go` 内 SyncPlanSubscriptionsTx 调用面（文件本体上游也有，本地对其增量当前未被上游触碰） |
| silent-batch 前端库 | `web/src/features/system-settings/lib/update-option-results.ts` |
| multikey 日志前端 | `web/src/features/usage-logs/lib/format-multikey.test.ts`；`web/src/features/usage-logs/components/columns/common-logs-columns.tsx` 内多键列显示（上游本次未碰；若未来上游改它，此项升级进 B 类） |
| 前端工程配置 | `web/.oxlintrc.json`、`web/rsbuild.config.ts` 改动、`web/index.html` 防闪烁脚本、`web/scripts/` i18n/format 脚本 |
| 样式 | `web/src/styles/theme.css` 黑白灰预设改造（另有 theme-presets.css 等） |
| 工具脚本 | `scripts/start-dev.ps1`、`scripts/release.bat`、`scripts/sync-script-tests.ps1`、`scripts/README.md` |
| 测试 | `service/codex_wham_usage_test.go` |
| 文档 | `docs/superpowers/**`、`docs/upstream-sync.md` 本手册 |
````

- [ ] **步骤 2：检查渲染后的文件顶部与末尾完整性**（运行）
  - 运行：`(Get-Content docs\upstream-sync.md | Measure-Object -Line).Lines`
  - 预期：≈ 110–130 行之间（截断异常时检查 Write 是否成功）。

- [ ] **步骤 3：Commit**

```powershell
git add docs/upstream-sync.md
git commit -m @'
docs(sync): 新增上游同步手册骨架（流程/门槛/A类清单）

Co-Authored-By: Claude <noreply@anthropic.com>
'@
```

---

## 任务 2：手册 B 类清单（B1–B11 全量落盘）

**文件：**
- 修改：`docs/upstream-sync.md`（在 A 类表格之后追加章节）

- [ ] **步骤 1：追加 B 类章节**

用 Edit 工具，将上文手册中最后一行：

```markdown
| 文档 | `docs/superpowers/**`、`docs/upstream-sync.md` 本手册 |
```

替换为如下内容（原行保留在最上方作为章节分隔锚）：

````markdown
| 文档 | `docs/superpowers/**`、`docs/upstream-sync.md` 本手册 |

## B 类：上游文件内的本地修改（覆盖后必须重放）

> 每项四要素：文件 / 内容 / grep 锚点 / 注意事项。「提取命令」可在任意轮次零漂移找回原始内容：`git show dev-backup-pre-sync:<path>`。

### B1 `setting/ratio_setting/model_ratio.go` — 本地价格条目

锚点（存在性校验）：`360GPT_S2_V9`（360 组首条目）。

三段插入，紧跟既有相邻行：
- `"gpt-3.5-turbo-0125": 0.25,` 之后插 `"babbage-002": 0.2,` 与 `"davinci-002": 1,`
- `"curie": 10,` 之后插 `"babbage": 10,` 与 `"ada": 10,`
- `"SparkDesk-v4.0": 1.2858,` 之后插 8 个 360 系条目：

```go
	"360GPT_S2_V9":                              0.8572,
	"360gpt-turbo":                              0.0858,
	"360gpt-turbo-responsibility-8k":            0.8572,
	"360gpt-pro":                                0.8572,
	"360gpt2-pro":                               0.8572,
	"embedding-bert-512-v1":                     0.0715,
	"embedding_s1_v1":                           0.0715,
	"semantic_similarity_s1_v1":                 0.0715,
```

注意事项：map 字面量缩进为 tab、key 对齐以 `gofmt -w` 收尾为准。

### B2 `web/src/features/usage-logs/lib/format.ts` — getMultiKeyIndex

锚点：`getMultiKeyIndex`。插入位置：`parseLogOther` 函数体结束后、`Get time color based on duration` 注释之前。上游版本已有 `import type { LogOtherData } from '../types'`，无需新增 import。

```ts
/**
 * Extract the selected multi-key index from parsed log metadata.
 *
 * The value is a key-list index, not a database ID or secret key content.
 */
export function getMultiKeyIndex(
  other: LogOtherData | null | undefined
): number | null {
  if (other?.admin_info?.is_multi_key !== true) return null

  const index = other.admin_info.multi_key_index
  if (
    typeof index !== 'number' ||
    !Number.isFinite(index) ||
    !Number.isInteger(index) ||
    index < 0
  ) {
    return null
  }

  return index
}
```

配套（A 类保留，无需重放）：`web/src/features/usage-logs/lib/format-multikey.test.ts`、`LogOtherData.admin_info` 类型字段位于 `web/src/features/usage-logs/types.ts`（上游未动）。

### B3 `web/src/features/usage-logs/components/dialogs/details-dialog.tsx` — 详情弹窗多键徽标

锚点：`multiKeyLabel`。三处改动：
1. 从 `'../../lib/format'` 具名导入列表中加一项 `getMultiKeyIndex,`（放在 `renderAuditContent,` 之后）。
2. 在 `const other = parseLogOther(props.log.other)` 与 `const typeConfig = ...` 两行之间插：

```tsx
  const multiKeyIndex = getMultiKeyIndex(other)
  const multiKeyLabel = multiKeyIndex === null ? null : `K${multiKeyIndex}`
  const multiKeyTitle =
    multiKeyIndex === null
      ? undefined
      : `${t('Key')} ${t('Index')}: ${multiKeyIndex}`
```

3. Channel 行 `value={<span>{props.log.channel}…</span>}` 整块替换为：

```tsx
                <span className='inline-flex flex-wrap items-center gap-1'>
                  <span>{props.log.channel}</span>
                  {props.log.channel_name && (
                    <span className='text-muted-foreground'>
                      ({props.log.channel_name})
                    </span>
                  )}
                  {multiKeyLabel && (
                    <StatusBadge
                      label={multiKeyLabel}
                      variant='neutral'
                      size='sm'
                      showDot={false}
                      copyable={false}
                      title={multiKeyTitle}
                      aria-label={multiKeyTitle}
                      className='border-border/60 bg-muted/40 font-mono'
                    />
                  )}
                </span>
```

依赖确认：上游文件已 import `StatusBadge`（自 `@/components/status-badge`）。观察项：`columns/common-logs-columns.tsx` 的列表多键列显示目前靠 merge 自然保留。

### B4 silent-batch 批量保存特性（前端四处 + 一个 A 类支撑文件）

锚点：`UpdateOptionMutationRequest`。特性语义：`updateOption.mutateAsync({...,silent:true})` 循环收集 results，中途失败即中止并失效相关 query；非 silent 才弹成功 toast。判定函数 `didAllOptionUpdatesSucceed` 来自 A 类文件 `web/src/features/system-settings/lib/update-option-results.ts`。

历史注记：本设计初稿曾把"嵌套计费 GroupGroupRatio/baseRatioByName"列为本项主体；考古证实其为双方共享特性（merge-base 已有），无需重放——真正要重放的只是下述调用面改动。

涉及文件与内容：
1. `web/src/features/system-settings/types.ts`：`UpdateOptionRequest` 类型之后新增：

```ts
export type UpdateOptionMutationRequest = UpdateOptionRequest & {
  /** 当为 true 时，不弹出成功提示（用于批量更新场景） */
  silent?: boolean
}
```

2. `web/src/features/system-settings/hooks/use-update-option.ts`：
   - `import type { UpdateOptionRequest } from '../types'` 改为 `import type { UpdateOptionMutationRequest } from '../types'`
   - mutation 定义改为：

```ts
  return useMutation({
    mutationFn: (request: UpdateOptionMutationRequest) => {
      const { silent, ...optionRequest } = request
      void silent
      return updateSystemOption(optionRequest)
    },
```

   - 成功 toast 包一层条件：`if (!variables.silent) { toast.success(...) }`

3. `web/src/features/system-settings/models/ratio-settings-card.tsx`：两处保存 handler（models 与 groups）内的更新循环改成 results 聚合形态（详见计划任务 6 内嵌代码；一轮一轮跟上游融合，保持上游变量名 normalized/savedModelValues 等）。

4. `web/src/features/models/components/drawers/model-mutate-drawer.tsx`：updates 循环改成 break-on-fail + 失败时 invalidate（详见计划任务 6）。

### B5 `web/src/styles/theme.css` — 黑白灰默认预设

锚点：`oklch(0.13 0 0)`。另涉 theme-presets.css 与 `web/index.html` 防闪烁 fallback。**上游至今未动这三个文件**，正常轮次零操作；一旦它们出现在某轮 `$both` 集合，从 `dev-backup-pre-sync` 提取整文件差量重放。

### B6 `CLAUDE.md` — 项目规则段

锚点：`Rule 9`。保持 Rule 5（保护信息）与 Rule 9（后端测试质量）两大段在位；superpowers-zh 框架段已被主动删除，**勿恢复**（同时见 C2）。上游至今未动此文件。

### B7 dockeronly 构建定制（四个构建文件各一行级）

| 文件 | 重放内容 |
|---|---|
| `.github/workflows/release.yml` | tags 过滤列表中 `'- *'` 行后加一行 `      - '!*-dockeronly*'` |
| `.github/workflows/electron-build.yml` | 同上位置加 `- '!*-dockeronly*' # Ignore docker-only tags` |
| `.gitignore` | 加 `*.rej`；删除 `plans` 忽略行；`.cursor` 之后加 `.superpowers`；`.playwright-mcp` 之后加 `.codegraph/` 与 `.zcode/` |
| `Dockerfile` | builder 阶段镜像固定 digest 写法换成 `FROM oven/bun:latest AS builder` |

锚点：`dockeronly`（yml）、`*.rej`（gitignore）、`oven/bun:latest`（Dockerfile）。

### B8 `model/subscription.go` — 计划变更同步存量订阅

锚点：`SyncPlanSubscriptionsTx`。在 `adminResetPlanSubscriptionsTx` 函数后、`func AdminResetUserSubscriptionsByPlan(` 之前插入 `SubscriptionPlanSyncResult` 结构体 + `SyncPlanSubscriptionsTx` 函数（约 72 行）。原文可用提取命令取得：`git show dev-backup-pre-sync:model/subscription.go` 中搜索 `SubscriptionPlanSyncResult reports`。
上游侧确认（2026-08 轮）：其实现的依赖 `calcNextResetTime`、`lockForUpdate`、`UserSubscription.AmountTotal/AmountUsed/NextResetTime/LastResetTime` 均仍在上游文件中。
调用方 `controller/subscription.go` 与回归测试 `model/subscription_sync_test.go` 都是本地侧独改/独有文件，merge 自然保留；仅当未来上游也动 `controller/subscription.go` 时才需要手工融合这两处。

### B9 `service/channel_affinity_usage_cache_test.go` — 测试 ID uuid 化

锚点：`uniqueChannelAffinityUsageCacheTestID`。重放内容：删 `"time"` import（若无其他引用）、加 `"github.com/google/uuid"` import，以及：

```go
func uniqueChannelAffinityUsageCacheTestID(prefix string) string {
	return prefix + "_" + uuid.NewString()
}
```

三个 Test 函数体内共 6 处 `fmt.Sprintf("rule_%d", time.Now().UnixNano())` 形式改为 `uniqueChannelAffinityUsageCacheTestID("rule")` / `("fp")`。背景：时间戳纳秒在并行测试下可能碰撞导致偶发失败。上游侧仍是 time 版本，故每轮都要重放。

### B10 杂项 lint/样式小组（逐文件单点）

锚点：`set-state-in-effect`。为通过本地 oxlint 规则而存在的抑制注释（规则来自 A 类 `web/.oxlintrc.json`；上游无此配置但其新代码落地后会在本地触发告警，注释无害）：

| 文件 | 在哪一行的正上方插哪一行 |
|---|---|
| `web/src/features/auth/sign-in/components/user-auth-form.tsx` | `setAgreedToLegal(false)` ← `// eslint-disable-next-line react-hooks/set-state-in-effect` |
| `web/src/features/channels/components/dialogs/balance-query-dialog.tsx` | `handleQueryCodexUsage()` ← 同上注释 |
| `web/src/features/channels/components/dialogs/fetch-models-dialog.tsx` | `handleFetchModels()` ← `// eslint-disable-next-line react-hooks/immutability`；另 `contentClassName='max-w-3xl'` → `'sm:max-w-3xl'` |
| `web/src/features/profile/components/tabs/account-bindings-tab.tsx` | `fetchCustomBindings()` ← set-state-in-effect 注释 |
| `web/src/features/system-settings/auth/oauth-section.tsx` | `<SettingsForm onSubmit={form.handleSubmit(onSubmit)}>` ← `{/* eslint-disable-next-line react-hooks/refs */}`；`onSave={form.handleSubmit(onSubmit)}` ← `// eslint-disable-next-line react-hooks/refs` |
| `web/src/features/users/components/dialogs/user-binding-dialog.tsx` | `setShowBoundOnly(true)` ← set-state-in-effect 注释 |
| `web/src/features/wallet/hooks/use-billing-history.ts` | `fetchBillingHistory()` ← set-state-in-effect 注释 |
| `web/src/features/models/components/drawers/model-mutate-drawer.tsx` | `setOldModelName(model.model_name)` ← set-state-in-effect 注释 |
| `web/src/features/system-settings/models/routing-reliability-section.tsx` | 见下方独立片段（基线序列化同步） |

routing-reliability-section 本地改进（防止 defaultValues 外部刷新后 baseline 过期）：
1. `const baselineRef = useRef<NormalizedRoutingReliabilityValues>(normalizeDefaults(defaultValues))` 声明之后加：

```tsx
  const baselineSerializedRef = useRef<string>(
    JSON.stringify(normalizeDefaults(defaultValues))
  )
```

2. `useResetForm(form, formDefaults)` 之后加：

```tsx
  useEffect(() => {
    const normalized = normalizeDefaults(defaultValues)
    const serialized = JSON.stringify(normalized)
    if (serialized === baselineSerializedRef.current) return
    baselineRef.current = normalized
    baselineSerializedRef.current = serialized
  }, [defaultValues])
```

3. handler 末尾 `baselineRef.current = normalized` 之后加一行 `baselineSerializedRef.current = JSON.stringify(normalized)`。
4. React import 需要 `useEffect`（缺则补）。
另有一处**有意放弃**：user-binding-dialog 中原 diff 还包含两个空行分隔，纯排版噪声，不重放。

### B11 i18n 六键七语

锚点：`Updated; synced {{count}} active subscriptions`（en/zh 等 7 个 locale 文件 `.translation` 下各应有 6 个本地键）。键全集（en 原文）：
1. `Apply changes to existing subscriptions`
2. `Pricing changes saved to draft. Click "Save model prices" to apply.`
3. `Draft`
4. `Will be removed`
5. `Sync the new quota and reset period to active subscribers. Used quota is kept.`
6. `Updated; synced {{count}} active subscriptions`

七语译文以 `dev-backup-pre-sync` 分支的 locale 文件为源，注入脚本见计划任务 9（比较 backup 与当前文件、按字母序插回、保持 2 空格缩进与结尾换行）。键 1/5/6 服务于 B8；键 2/3/4 服务于 ratio 表单草稿交互；任何人新增 UI 文案时，对应键值必须当次补录（开发习惯条款）。
````

- [ ] **步骤 2：B 类条目计数自检**（运行）
  - 运行：`(Select-String -Path docs\upstream-sync.md -Pattern '^### B\d').Count`
  - 预期：`11`

- [ ] **步骤 3：Commit**

```powershell
git add docs/upstream-sync.md
git commit -m @'
docs(sync): 手册补齐 B 类清单 B1-B11（代码块/锚点/注意事项）

Co-Authored-By: Claude <noreply@anthropic.com>
'@
```

---

## 任务 3：手册 C 类清单 + 锚点索引 + 收口自检

**文件：**
- 修改：`docs/upstream-sync.md`

- [ ] **步骤 1：追加 C 类与锚点索引**

用 Edit 工具，old_string 使用以下整段（B11 小节末段，全文唯一）：

```markdown
七语译文以 `dev-backup-pre-sync` 分支的 locale 文件为源，注入脚本见计划任务 9（比较 backup 与当前文件、按字母序插回、保持 2 空格缩进与结尾换行）。键 1/5/6 服务于 B8；键 2/3/4 服务于 ratio 表单草稿交互；任何人新增 UI 文案时，对应键值必须当次补录（开发习惯条款）。
```

替换为「该段落原样保留 + 追加以下内容」：

````markdown
## C 类：主动放弃的上游特性（每轮合并重新决策，防静默带回）

| # | 特性 | 放弃原因 | 涉及文件与本轮剔除动作 |
|---|---|---|---|
| C1 | unset-models 价格页签（默认 tab 与 variant 入口） | 与本地 silent-batch 流程冲突、产品上不需要该入口 | 取上游版后在 `section-registry.tsx` 把 Model Pricing 的 visibleTabs 数组删去 `'unset-models'`；在 `ratio-settings-card.tsx` 从 RatioTabId 联合类型、tabLabels、renderTabContent 分支（连同 `variant=` 属性行）删去 unset-models 相关成员。具体代码见手册随附计划任务 6 |
| C2 | superpowers-zh 框架段（CLAUDE.md） | 2026-07-14 主动删除 | 若任何来源试图恢复 CLAUDE.md 该段落，拒绝并维持删除状态 |

## 锚点速查索引（第 4 步机械校验用；PowerShell 直接粘贴）

```powershell
$pairs = @(
  @('setting/ratio_setting/model_ratio.go','360GPT_S2_V9')
  @('web/src/features/usage-logs/lib/format.ts','getMultiKeyIndex')
  @('web/src/features/usage-logs/lib/format-multikey.test.ts','getMultiKeyIndex')
  @('web/src/features/usage-logs/components/dialogs/details-dialog.tsx','multiKeyLabel')
  @('web/src/features/system-settings/types.ts','UpdateOptionMutationRequest')
  @('web/src/features/system-settings/hooks/use-update-option.ts','silent')
  @('web/src/features/system-settings/lib/update-option-results.ts','didAllOptionUpdatesSucceed')
  @('web/src/styles/theme.css','oklch(0.13 0 0)')
  @('CLAUDE.md','Rule 9')
  @('.github/workflows/release.yml','dockeronly')
  @('.github/workflows/electron-build.yml','dockeronly')
  @('.gitignore','*.rej')
  @('Dockerfile','oven/bun:latest')
  @('model/subscription.go','SyncPlanSubscriptionsTx')
  @('controller/subscription.go','SyncPlanSubscriptionsTx')
  @('model/subscription_sync_test.go','SyncPlanSubscriptionsTx')
  @('service/channel_affinity_usage_cache_test.go','uniqueChannelAffinityUsageCacheTestID')
  @('web/src/features/users/components/dialogs/user-binding-dialog.tsx','set-state-in-effect')
  @('web/src/i18n/locales/en.json','Updated; synced {{count}} active subscriptions')
  @('web/src/i18n/locales/zh.json','将变更同步到已绑定订阅')
)
foreach ($p in $pairs) {
  $hit = (Select-String -Path $p[0] -Pattern $p[1] -SimpleMatch | Measure-Object).Count
  if ($hit -ge 1) { "PASS $($p[0]) <- $($p[1])" } else { "FAIL $($p[0]) <- $($p[1])" }
}
```

反向断言（C 类确已缺席，二者都应 FAIL=True）：
`Select-String -Path web/src/features/system-settings/models/ratio-settings-card.tsx -Pattern 'unset-models' -SimpleMatch` 无命中；
`Select-String -Path CLAUDE.md -Pattern 'superpowers-zh' -SimpleMatch` 无命中。

## 手册维护纪律

1. 任何在 B/C 清单之外产生的本地新个性化（无论文件内条目还是整文件），合入当次必须同 commit 或紧随 commit 补录手册，并给 grep 锚点。
2. 每轮同步收尾时：更新 `$replayFiles` 与锚点索引为当次真实状态；把当次 merge-base 与 upstream 领先数写入本节下方「轮次记录」。
3. 「提取命令」惯例：历史真相永远在 `dev-backup-pre-sync`，手册描述原则，提取命令交付字节。

## 轮次记录

| 日期 | merge-base | upstream 领先 | 备注 |
|---|---|---|---|
| 2026-08-26 | bc14c18f6024e79cba1c08d02cd007796e12d668 | 83 commits | 手册首轮实战；封面考古结论：嵌套计费属共享基底；B 清单定稿 B1-B11 |
````

- [ ] **步骤 2：三段结构完整自检**（运行）
  - `(Select-String -Path docs\upstream-sync.md -Pattern '^## ').Count` 预期 ≥ 8（核心模式/流程/门槛/漂移/A/B/C/锚点/纪律/轮次 中出现的小节数）
  - `(Select-String -Path docs\upstream-sync.md -Pattern '锚点速查索引').Count` 预期 `≥ 1`

- [ ] **步骤 3：Commit**

```powershell
git add docs/upstream-sync.md
git commit -m @'
docs(sync): 手册收口：C类清单、锚点索引、维护纪律与轮次记录

Co-Authored-By: Claude <noreply@anthropic.com>
'@
```

---

## 任务 4：执行第 1~2 步 —— 备份 + 合并 + 30 文件全覆盖 + merge commit

**文件：**
- 影响：整个仓库（工作树）；提交对象为一个 merge commit。

- [ ] **步骤 1：前置清洁与备份分支**

```powershell
git status --porcelain        # 预期空输出
git branch --list dev-backup-pre-sync   # 若存在旧快照：git branch -D dev-backup-pre-sync
git branch dev-backup-pre-sync
git rev-parse --short dev-backup-pre-sync
```

- [ ] **步骤 2：抓取上游并现算双方都改集合**

```powershell
git fetch upstream
$mb = git merge-base dev upstream/main
echo "MERGE-BASE=$mb"
git rev-list --count "$mb..upstream/main"
$localChanged = git diff --name-only $mb dev
$upstreamChanged = git diff --name-only $mb upstream/main
$both = @($localChanged | Where-Object { $upstreamChanged -contains $_ })
$both.Count
$both
```

预期：count = 83（若上游又推进了：允许 >83，但 `$both` 与计划头部清单的差异必须逐一归因并先补录手册再继续）。

- [ ] **步骤 3：合并并整文件覆盖**

```powershell
git merge --no-commit --no-ff upstream/main
# 冲突与否都不手工三选一；对 $both 内每个文件无条件整文件取上游：
foreach ($f in $both) { git checkout upstream/main -- $f }
git status --porcelain | Select-String '^UU|^AA|^DD'
```

预期最后一条命令**无输出**（无遗留冲突标记状态）。若有：停，按手册五步流程第 2 步括号条款处理并补录手册。

- [ ] **步骤 4：提交 merge commit**

```powershell
git commit -m @'
merge(upstream): 全量覆盖同步 upstream/main (83 commits, merge-base bc14c18f)

按 docs/upstream-sync.md 五步流程执行第 2 步：双方都改 30 文件一律
整文件取上游版，本地个性化随后按 B 类清单重放（见后续 commits）。

Co-Authored-By: Claude <noreply@anthropic.com>
'@
git log --oneline -1
```

- [ ] **步骤 5：安装上游新增前端依赖**

```powershell
Push-Location web; bun install; Pop-Location
```

预期：lockfile 变更（vitest、testing-library 等入库）。此时 `git status` 会出现 `web/bun.lock`（也许还有 `package.json`）待后续一并纳入——若 package.json 变了属于上游 merge 已包含的内容，bun.lock 变化留到任务 9 后统一 commit。

---

## 任务 5：重放 Go 侧 B1 / B8 / B9 与构建定制 B7

**文件：**
- 修改：`setting/ratio_setting/model_ratio.go`、`model/subscription.go`、`service/channel_affinity_usage_cache_test.go`、`.github/workflows/release.yml`、`.github/workflows/electron-build.yml`、`.gitignore`、`Dockerfile`

- [ ] **步骤 1：B1 model_ratio.go 三段插入**

打开 `setting/ratio_setting/model_ratio.go`，按 B1 条目在三处锚行后插入（Edit 工具，old_string 用锚行本身）：
- 锚 `"gpt-3.5-turbo-0125":                        0.25,` 之后追加：

```go
	"babbage-002":                               0.2,
	"davinci-002":                               1,
```

- 锚 `"curie":                                     10,` 之后追加：

```go
	"babbage":                                   10,
	"ada":                                       10,
```

- 锚 `"SparkDesk-v4.0":                            1.2858,` 之后追加：

```go
	"360GPT_S2_V9":                              0.8572,
	"360gpt-turbo":                              0.0858,
	"360gpt-turbo-responsibility-8k":            0.8572,
	"360gpt-pro":                                0.8572,
	"360gpt2-pro":                               0.8572,
	"embedding-bert-512-v1":                     0.0715,
	"embedding_s1_v1":                           0.0715,
	"semantic_similarity_s1_v1":                 0.0715,
```

（若上游格式化了相邻行的空白对齐，沿用上游风格即可，gofmt 会统一。）

- [ ] **步骤 2：B8 subscription.go 插入 72 行块**

在 `model/subscription.go` 中定位 `func AdminResetUserSubscriptionsByPlan(`，把以下块整体插在它前面（等价于任务档案中备份分支的同名内容；上游对周边有过演进，若编译报错优先怀疑上游签名变化，按报错微调而非照抄旧行为）：

```go
// SubscriptionPlanSyncResult reports the outcome of syncing plan changes to
// existing active subscriptions. Mirrors SubscriptionResetResult shape for UI.
type SubscriptionPlanSyncResult struct {
	PlanId          int    `json:"plan_id"`
	MatchedCount    int    `json:"matched_count"`
	SyncedCount     int    `json:"synced_count"`
	UserCount       int    `json:"user_count"`
	PlanTitle       string `json:"-"`
	AffectedUserIds []int  `json:"-"`
}

// syncPlanSubscriptionsTx applies plan-level changes (total amount + reset
// period) to every active subscription under the plan within the caller's
// transaction. Used when an admin edits a plan and opts to sync existing
// subscribers. amount_used is preserved; it is only clamped down to the new
// total when the new total is smaller than what was already consumed, so a
// sync never produces a credit or overflow. The reset schedule begins at the
// synchronization time, preventing a new, shorter period from immediately
// resetting an existing subscriber's used quota.
func SyncPlanSubscriptionsTx(tx *gorm.DB, plan *SubscriptionPlan, now int64) (*SubscriptionPlanSyncResult, error) {
	if tx == nil || plan == nil {
		return nil, errors.New("invalid sync args")
	}
	var subs []UserSubscription
	if err := lockForUpdate(tx).
		Where("plan_id = ? AND status = ? AND end_time > ?", plan.Id, "active", now).
		Order("user_id asc, end_time asc, id asc").
		Find(&subs).Error; err != nil {
		return nil, err
	}
	for i := range subs {
		sub := &subs[i]
		sub.AmountTotal = plan.TotalAmount
		// Clamp used to the new total when it shrank below consumed amount.
		// A zero total means unlimited and never clamps.
		if sub.AmountTotal > 0 && sub.AmountUsed > sub.AmountTotal {
			sub.AmountUsed = sub.AmountTotal
		}
		// Start the new reset schedule at sync time. Using an older reset time
		// could leave the computed deadline in the past and immediately clear
		// amount_used in the reset task.
		nextReset := calcNextResetTime(time.Unix(now, 0), plan, sub.EndTime)
		sub.NextResetTime = nextReset
		if nextReset > 0 {
			sub.LastResetTime = now
		} else {
			sub.LastResetTime = 0
		}
		if err := tx.Save(sub).Error; err != nil {
			return nil, err
		}
	}
	// Deduplicate affected user ids for downstream audit/cache invalidation.
	userIds := make([]int, 0, len(subs))
	seenUsers := make(map[int]struct{}, len(subs))
	for _, sub := range subs {
		if _, ok := seenUsers[sub.UserId]; ok {
			continue
		}
		seenUsers[sub.UserId] = struct{}{}
		userIds = append(userIds, sub.UserId)
	}
	return &SubscriptionPlanSyncResult{
		PlanId:          plan.Id,
		MatchedCount:    len(subs),
		SyncedCount:     len(subs),
		UserCount:       len(userIds),
		PlanTitle:       plan.Title,
		AffectedUserIds: userIds,
	}, nil
}
```

- [ ] **步骤 3：B9 channel_affinity 测试 uuid 化**

`service/channel_affinity_usage_cache_test.go`：
1. import 块：删除 `"time"`（若上游文件还有其他 time 引用则保留并报告），添加 `"github.com/google/uuid"`（字母序置于 gin 与 testify 之间偏前位置）。
2. `buildChannelAffinityStatsContextForTest` 函数之后插入：

```go
func uniqueChannelAffinityUsageCacheTestID(prefix string) string {
	return prefix + "_" + uuid.NewString()
}
```

3. 三个 TestObserveChannelAffinityUsageCacheByRelayFormat_* 函数里，把六处
   `ruleName := fmt.Sprintf("rule_%d", time.Now().UnixNano())` 全部换成 `ruleName := uniqueChannelAffinityUsageCacheTestID("rule")`，
   六处中的 `keyFP := fmt.Sprintf("fp_%d", time.Now().UnixNano())` 全部换成 `keyFP := uniqueChannelAffinityUsageCacheTestID("fp")`。

- [ ] **步骤 4：B7 构建文件一行级定制**

- `.github/workflows/release.yml`：tags 列表 `'- *-alpha*'` 行下加一行（保持同级缩进 6 空格）`      - '!*-dockeronly*'`
- `.github/workflows/electron-build.yml`：`'- *-alpha*'` 行下加 `      - '!*-dockeronly*' # Ignore docker-only tags`
- `.gitignore`：`*.exe` 行后加 `*.rej`；删除单独一行 `plans`；`.cursor` 行后加 `.superpowers`；`.playwright-mcp` 行后加 `.codegraph/` 与 `.zcode/` 两行
- `Dockerfile`：首行 `FROM oven/bun:1@sha256:0733e50325078969732ebe3b15ce4c4be5082f18c4ac1a0f0ca4839c2e4e42a7 AS builder` 改为 `FROM oven/bun:latest AS builder`

- [ ] **步骤 5：快速编译与定向 Go 校验**

```powershell
gofmt -w setting\ratio_setting\model_ratio.go model\subscription.go service\channel_affinity_usage_cache_test.go
go build ./...
go test ./model/ -run Subscription
go test ./service/ -run TestObserveChannelAffinityUsageCache
```

预期：全部 exit 0。

- [ ] **步骤 6：两个 Commit（B1+B8+B9 一个、B7 一个）**

```powershell
git add setting/ratio_setting/model_ratio.go model/subscription.go service/channel_affinity_usage_cache_test.go
git commit -m @'
feat(local): 重放 B1 价格条目 / B8 订阅计划同步 / B9 测试 uuid 化

Co-Authored-By: Claude <noreply@anthropic.com>
'@
git add .github/workflows/release.yml .github/workflows/electron-build.yml .gitignore Dockerfile
git commit -m @'
build(dockeronly): 重放 B7 构建与忽略文件定制

Co-Authored-By: Claude <noreply@anthropic.com>
'@
```

---

## 任务 6：重放前端 silent-batch 特性（B4）并剔除 unset-models（C1）

**文件：**
- 修改：`web/src/features/system-settings/types.ts`、`web/src/features/system-settings/hooks/use-update-option.ts`、`web/src/features/system-settings/models/ratio-settings-card.tsx`、`web/src/features/system-settings/billing/section-registry.tsx`、`web/src/features/models/components/drawers/model-mutate-drawer.tsx`

前置：任务 4 步骤 5 的 `bun install` 已完成。

- [ ] **步骤 1：types.ts 增加 mutation 请求类型**

在 `export type UpdateOptionResponse = {` 之前插入：

```ts
export type UpdateOptionMutationRequest = UpdateOptionRequest & {
  /** 当为 true 时，不弹出成功提示（用于批量更新场景） */
  silent?: boolean
}
```

- [ ] **步骤 2：use-update-option.ts 接入 silent**

1. `import type { UpdateOptionRequest } from '../types'` → `import type { UpdateOptionMutationRequest } from '../types'`
2. `mutationFn: (request: UpdateOptionRequest) => updateSystemOption(request),` 替换为：

```ts
    mutationFn: (request: UpdateOptionMutationRequest) => {
      const { silent, ...optionRequest } = request
      void silent
      return updateSystemOption(optionRequest)
    },
```

3. 成功分支中 `toast.success(i18next.t('Setting updated successfully'))` 替换为：

```ts
        if (!variables.silent) {
          toast.success(i18next.t('Setting updated successfully'))
        }
```

- [ ] **步骤 3：ratio-settings-card.tsx 融合两处保存循环（C1 + B4 同时落位）**

3a. 先做 C1 剔除（基于上游版文件）：
- 联合类型改为 `type RatioTabId = 'models' | 'groups' | 'tool-prices' | 'upstream-sync'`（删除 `| 'unset-models'` 行）
- `tabLabels` 里删除 `'unset-models': 'Unset price models',` 一行
- `renderTabContent` 中 `if (tab === 'models' || tab === 'unset-models') {` 改为 `if (tab === 'models') {`，并删除 `<ModelRatioForm …>` 里的 `variant={tab === 'unset-models' ? 'unset' : 'default'}` 属性行（本地 ModelRatioForm 无 variant 概念）

3b. models 保存 handler：把上游的

```ts
        for (const key of updates) {
          const apiKey = apiKeyMap[key as string] || (key as string)
          await updateOption.mutateAsync({ key: apiKey, value: normalized[key] })
        }

        modelNormalizedDefaults.current = normalized
        setSavedModelValues(normalized)
      },
      [t, updateOption]
```

改为：

```ts
        const results = []
        for (const key of updates) {
          const result = await updateOption.mutateAsync({
            key: apiKeyMap[key as string] || (key as string),
            value: normalized[key],
            silent: true,
          })
          results.push(result)
          if (!result.success) return
        }
        if (results.length > 0 && didAllOptionUpdatesSucceed(results)) {
          toast.success(t('Setting updated successfully'))
        }

        modelNormalizedDefaults.current = normalized
        setSavedModelValues(normalized)
      },
      [t, updateOption]
```

3c. groups 保存 handler：把上游的

```ts
        for (const key of updates) {
          const apiKey = apiKeyMap[key] || key
          await updateOption.mutateAsync({ key: apiKey, value: normalized[key] })
        }

        groupNormalizedDefaults.current = normalized
      },
      [updateOption]
```

改为：

```ts
        const results = []
        for (const key of updates) {
          const result = await updateOption.mutateAsync({
            key: apiKeyMap[key] || key,
            value: normalized[key],
            silent: true,
          })
          results.push(result)
          if (!result.success) return
        }
        if (results.length > 0 && didAllOptionUpdatesSucceed(results)) {
          toast.success(t('Setting updated successfully'))
        }

        groupNormalizedDefaults.current = normalized
      },
      [t, updateOption]
```

顶部补 import：`import { didAllOptionUpdatesSucceed } from '../lib/update-option-results'`（放置于 `../hooks/use-update-option` 导入行之后）。

- [ ] **步骤 4：section-registry.tsx 剔除 unset-models**

`visibleTabs={['models', 'unset-models', 'tool-prices', 'upstream-sync']}` → `visibleTabs={['models', 'tool-prices', 'upstream-sync']}`

- [ ] **步骤 5：model-mutate-drawer.tsx 循环改造**

上游的：

```ts
              // Apply all updates (including deletions when clearing fields)
              for (const update of updates) {
                await updateOption.mutateAsync(update)
              }
```

改为：

```ts
              // Apply all updates (including deletions when clearing fields)
              const results = []
              for (const update of updates) {
                const result = await updateOption.mutateAsync({
                  ...update,
                  silent: true,
                })
                results.push(result)
                if (!result.success) break
              }

              if (results.length > 0 && !didAllOptionUpdatesSucceed(results)) {
                queryClient.invalidateQueries({
                  queryKey: modelsQueryKeys.lists(),
                })
                queryClient.invalidateQueries({ queryKey: ['system-options'] })
                return
              }
```

import 补充：`import { didAllOptionUpdatesSucceed } from '@/features/system-settings/lib/update-option-results'`（放进现有 system-settings import 区域；`queryClient`/`modelsQueryKeys` 上游版本已在作用域内，无需重复声明）。

- [ ] **步骤 6：typecheck 验证**

```powershell
Push-Location web; bun run typecheck; Pop-Location
```

预期 exit 0。若 `variant`/`savedValues` 之类 prop 因 C1 剔除引发报错，按"本地 ModelRatioForm 为准"修掉引用面后重跑。

- [ ] **步骤 7：Commit**

```powershell
git add web/src/features/system-settings/types.ts web/src/features/system-settings/hooks/use-update-option.ts web/src/features/system-settings/models/ratio-settings-card.tsx web/src/features/system-settings/billing/section-registry.tsx web/src/features/models/components/drawers/model-mutate-drawer.tsx
git commit -m @'
feat(web): 重放 B4 silent-batch 保存特性，同时剔除 C1 unset-models 页签

Co-Authored-By: Claude <noreply@anthropic.com>
'@
```

---

## 任务 7：重放多键显示（B2/B3）+ 仪表盘遮蔽用例（vitest 化）

**文件：**
- 修改：`web/src/features/usage-logs/lib/format.ts`、`web/src/features/usage-logs/components/dialogs/details-dialog.tsx`、`web/src/features/dashboard/lib/flow.test.ts`

- [ ] **步骤 1：format.ts 插入 getMultiKeyIndex（B2 正文见手册 B2 代码块）**

Edit 锚：`/**\n * Get time color based on duration` 之前插入该函数；确认文件顶部 `import type { LogOtherData } from '../types'` 存在（上游版自带）。

- [ ] **步骤 2：details-dialog.tsx 三处改动（B3）**

按手册 B3 三步：导入列表加 `getMultiKeyIndex,`；`parseLogOther` 行后插三行 const；Channel 行 value 块整换为带 StatusBadge 的包装版本。

- [ ] **步骤 3：flow.test.ts 以 vitest 语法重放遮蔽用例**

在上游 vitest 版文件内，定位 `test('builds Sankey spec with quota token request tooltips'` （不存在则以 describe 块末尾为准），其前插入：

```ts
  test('masks sensitive filter labels when sensitive data is hidden', () => {
    const result = buildDashboardFlowData(rows, 'quota', {
      role: 'root',
      maskSensitive: true,
    })

    expect(result.filterOptions.users.map((user) => user.label)).toEqual([
      '••••',
      '••••',
    ])
    const sensitiveNodeLabels = result.filterOptions.nodes
      .filter((node) => node.kind !== 'model')
      .map((node) => node.label)
    expect(sensitiveNodeLabels).toHaveLength(10)
    expect(sensitiveNodeLabels.every((label) => label === '••••')).toBe(true)
    expect(
      result.filterOptions.nodes
        .filter((node) => node.kind === 'model')
        .map((node) => node.label)
    ).toEqual(['gpt-4.1', 'claude-4-sonnet'])
  })
```

背景：上游把该文件从 node:test 迁到 vitest；`maskSensitive` 能力来自本地独改的 `flow.ts`（上游未动该库），故测试约束的是本地扩展行为。

- [ ] **步骤 4：typecheck + 定向 vitest**

```powershell
Push-Location web; bun run typecheck; Pop-Location
Push-Location web; bun run test -- src/features/dashboard/lib/flow.test.ts; Pop-Location
```

预期：typecheck 0；vitest 通过（若上游对新依赖的 jsdom 环境有额外要求导致 runner 起不来，记录输出并在任务 11 一并评估，不阻塞本 commit）。

- [ ] **步骤 5：Commit**

```powershell
git add web/src/features/usage-logs/lib/format.ts web/src/features/usage-logs/components/dialogs/details-dialog.tsx web/src/features/dashboard/lib/flow.test.ts web/bun.lock web/package.json
git commit -m @'
feat(web): 重放 B2/B3 多键索引显示与仪表盘敏感信息遮蔽用例（vitest 化）

顺带落盘上游带来的 bun.lock/package.json 依赖变化。

Co-Authored-By: Claude <noreply@anthropic.com>
'@
```

---

## 任务 8：重放杂项 lint 注释与 routing-reliability 基线效果（B10）

**文件：**
- 修改：手册 B10 表格列出的 9 个前端文件

- [ ] **步骤 1：逐文件插入抑制注释与样式修正**

严格按手册 B10 表格九行逐项执行（每处都是"锚行正上方插入注释"的单行 Edit；fetch-models-dialog 同时做 `max-w-3xl` → `sm:max-w-3xl` 替换）。完成后抽查：

```powershell
Select-String -Path web\src\features\system-settings\auth\oauth-section.tsx -Pattern 'react-hooks/refs' | Measure-Object
Select-String -Path web\src\features\wallet\hooks\use-billing-history.ts -Pattern 'set-state-in-effect'
```

预期：oauth-section 计数 ≥ 2；use-billing-history 有命中。

- [ ] **步骤 2：routing-reliability-section.tsx 基线序列化三步**

按手册 B10 最后一段：serializedRef 声明、useEffect 块、handler 尾行三者逐一插入；React import 缺 `useEffect` 则补。

- [ ] **步骤 3：oxlint 信息性运行（不设卡）**

```powershell
Push-Location web; bun run lint; Pop-Location
```

预期：登记剩余告警数（很多来自尚未抑制的上游新代码亦可接受；目标是不比合并前的 dev 更糟——若明显恶化，把新增噪音计入下一轮 B10 待办，不回滚本轮）。

- [ ] **步骤 4：Commit**

```powershell
git add web/src
git commit -m @'
chore(web): 重放 B10 lint 抑制注释与路由可靠性基线同步效果

Co-Authored-By: Claude <noreply@anthropic.com>
'@
```

---

## 任务 9：重放 i18n 六键七语（B11）

**文件：**
- 修改：`web/src/i18n/locales/{en,zh,zh-TW,fr,ru,ja,vi}.json`

- [ ] **步骤 1：从备份分支机械注入缺失键**

```powershell
$code = @'
const { execSync } = require('child_process')
const fs = require('fs')
const langs = ['en','zh','zh-TW','fr','ru','ja','vi']
for (const lang of langs) {
  const path = `web/src/i18n/locales/${lang}.json`
  const backupRaw = execSync(`git show dev-backup-pre-sync:${path}`, {encoding:'utf8', maxBuffer: 64*1024*1024})
  const backupKeys = Object.keys(JSON.parse(backupRaw).translation)
  const curRaw = fs.readFileSync(path, 'utf8')
  const cur = JSON.parse(curRaw)
  let injected = 0
  for (const k of backupKeys) {
    if (!(k in cur.translation)) { cur.translation[k] = JSON.parse(backupRaw).translation[k]; injected++ }
  }
  // 保持既有扁平结构与排序习惯：按键名字典序重排 translation（i18n:sync 同款行为）
  const sortedTranslation = {}
  for (const k of Object.keys(cur.translation).sort()) sortedTranslation[k] = cur.translation[k]
  fs.writeFileSync(path, JSON.stringify({ translation: sortedTranslation }, null, 2) + '\n')
  console.log(`${lang}: injected=${injected}`)
}
'@
$code | Out-File -Encoding utf8NoBOM "$env:TEMP\inject-local-i18n.cjs"
node "$env:TEMP\inject-local-i18n.cjs"
Remove-Item "$env:TEMP\inject-local-i18n.cjs"
```

预期输出：每行 `injected=6` 共 7 行。（若合并前后还有别的本地键因某轮补录进了 backup，也会被一起救回，数量 >6 属正常但要核对键名。）

- [ ] **步骤 2：验证键数与格式安全**

```powershell
node -e "const j=require('./web/src/i18n/locales/zh.json');console.log(Object.keys(j.translation).length)"
Push-Location web
bun run i18n:sync
Pop-Location
git status --porcelain web/src/i18n | Select-Object -First 10
```

预期：键数 ≥ backup 分支的键数；`i18n:sync` 后工作区不再产生新的意外 diff（若 i18n:sync 改写了文件，说明我们写的格式与工具期待不一致，接受工具化的结果并纳入本次 commit）。

- [ ] **步骤 3：format:check 只读校验**

```powershell
Push-Location web; bun run format:check; Pop-Location
```

预期能跑完；locale JSON 若报格式问题：手工对照 backup 分支的原始排版修复受影响文件，**绝不允许跑 format --write**。

- [ ] **步骤 4：Commit**

```powershell
git add web/src/i18n/locales
git commit -m @'
chore(i18n): 重放 B11 七语言六个本地键（源自 dev-backup-pre-sync 机械注入）

Co-Authored-By: Claude <noreply@anthropic.com>
'@
```

---

## 任务 10：锚点全量校验 + 漂移检测

**文件：** 无新改动；不通过则回到对应任务修补后重来本校验。

- [ ] **步骤 1：跑手册锚点索引脚本（含正向 20 对 + 反向 2 断言）**

直接复制手册「锚点速查索引」代码块执行，预期全 PASS、零 FAIL；反向断言均确认为"无命中"。任一 FAIL：定位对应任务补重放，然后重跑直到全绿。

- [ ] **步骤 2：跑手册漂移检测脚本**

直接复制手册「漂移检测脚本」执行，预期无 `FAIL` 输出行。出现 FAIL 时逐条归因：上游变更 → 正常；清单外本地差异 → 补录 B 项并补重放；A 类文件变动 → 查误操作（可用 `git diff dev-backup-pre-sync -- <file>` 对照恢复）。

---

## 任务 11：验证门槛 + 收尾

**文件：** 无常规改动；只允许门槛驱动的最小修复。

- [ ] **步骤 1：门槛 1-3（Go 构建 + 后端定向测试 + web 构建链）**

```powershell
go build ./...
go test ./common/... ./pkg/billingexpr/... ./relay/common/... ./setting/ratio_setting/... ./relay/channel/ai360/...
go test ./model/ -run Subscription
Push-Location web; bun run typecheck; Pop-Location
Push-Location web; bun run build; Pop-Location
```

预期全部 exit 0。

- [ ] **步骤 2：门槛 4（信息性：前端 vitest 全量）**

```powershell
Push-Location web; bun run test; Pop-Location
```

记录失败清单。判定标准：与 `dev-backup-pre-sync` 上跑同一套（`bunx vitest run` 在 backup worktree 可跳过，通常本地库为本地独改、上游新测试对本地上游未动库应兼容）相比**不得新增红测**；flow.test 必须绿。

- [ ] **步骤 3：门槛 5+6（format:check 与保护文件核对）**

```powershell
Push-Location web; bun run format:check; Pop-Location
git diff dev-backup-pre-sync -- CLAUDE.md web/src/styles/theme.css
git log --oneline dev-backup-pre-sync..dev
```

预期：第一条 exit 0（失败则手工修行，禁 --write）；第二条 diff 仅允许包含 B5/B6 声明过的内容（本轮两者皆不应有 → 空 diff）；第三条可见 merge commit + 约 8 个重放 commit。

- [ ] **步骤 4：收尾报告**

向用户汇报：merge-base、upstream commits 数、覆盖文件数、每条 B 项的落位证据（锚点 grep 通过明细）、漂移检测与全部门槛结果、backup 分支保留提示（回滚指令：未 push 前 `git reset --hard dev-backup-pre-sync`）。**不做 push、不开 PR**（等待用户明确指示）。

---

## 自检记录（写计划时已完成）

1. **规格覆盖度**：设计 §核心模式/风险对策 → 任务 4 全覆盖 + 任务 10 校验；§手册三清单 → 任务 1-3；§五步流程 → 任务 4-10 对应关系见各任务标题；§验证门槛 → 任务 11；§范围（83 commits）→ 任务 4 步骤 2 断言；§回滚 → 任务 4 步骤 1 与任务 11 步骤 4。
2. **占位符扫描**：所有代码步骤均给出实际代码或精确复制的执行命令；唯一的过程性引用指向手册中的完整脚本（同一文档内已全文嵌入）。
3. **类型一致性**：`UpdateOptionMutationRequest`（types.ts）↔ use-update-option/drawer/card 调用一致；`SyncPlanSubscriptionsTx`/`SubscriptionPlanSyncResult` 与 `controller/subscription.go`、`model/subscription_sync_test.go` 既有调用一致；`getMultiKeyIndex(multiKeyLabel/multiKeyTitle/multiKeyIndex)` 命名跨 B2/B3 一致；`uniqueChannelAffinityUsageCacheTestID` 命名与既有测试用途一致。
