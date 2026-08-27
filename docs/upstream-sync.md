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
6. 保护文件核对：
   ```powershell
   git diff dev-backup-pre-sync -- CLAUDE.md web/src/styles/theme.css
   ```
   CLAUDE.md 在本轮以后若进入双方都改集合，重放项 B6 生效后此 diff 只允许等于 B6 内容。theme.css 已于 2026-08-27 退役黑白灰预设并取上游版——该文件相对备份的 diff 应等于「备份当时的本地改造取反」，不再要求为空；更直接的校验是 `git diff upstream/main -- web/src/styles/theme.css` 必须为空。

## 漂移检测脚本（第 5 步直接粘贴运行）

```powershell
$backup = 'dev-backup-pre-sync'
$mb = git merge-base $backup upstream/main
$changed      = @(git diff --name-only "$backup..dev")
$both         = @(git diff --name-only "$mb..$backup" | Where-Object { (git diff --name-only "$mb..upstream/main") -contains $_ })
# 1) 重放过但不含任何 B 项的覆盖文件：最终态必须与 upstream/main 完全一致
#    （含 B 项的文件在下面 $replayFiles 里列出，豁免该断言）
$replayFiles = @(
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
  'web/src/features/system-settings/models/ratio-settings-card.tsx'
  'web/src/features/system-settings/models/routing-reliability-section.tsx'
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
  $changedSinceBackup = git diff --name-only "$backup..dev" -- $f
  if ($changedSinceBackup) { "FAIL 仅本地文件被动了`t$f" }
}
"漂移检测结束。没有 FAIL 行即通过。"
```

> 勘误（2026-08-27）：第 2 段循环初稿为 `if (-not (git diff --quiet "$backup..dev" -- $f))`。PowerShell 中原生命令的退出码不进输出流，而 `--quiet` 成功时又无任何 stdout，该条件恒成立，导致所有仅本地文件被误报 FAIL。现用「`git diff --name-only` 输出非空」判定；在终端里验证退出码请写 `git diff --quiet ...; if ($LASTEXITCODE -ne 0) {...}`。

## A 类：本地独有文件（上游无对应文件，merge 天然保留）

盘点目的：防误删、让新会话快速了解本地特性面。按目录分组（较完整枚举，散件忽略）：

| 组 | 内容 |
|---|---|
| relay 适配 | `relay/channel/ai360/`（360AI 渠道适配 + 敏感数据遮蔽，注意上游历史里也有同名目录，属共享基底，本地在其上叠了一个 feature commit）；含 `constants_test.go` 模型列表回归 |
| 订阅特性后端 | `model/subscription_sync_test.go`；`controller/subscription.go` 内 SyncPlanSubscriptionsTx 调用面（文件本体上游也有，本地对其增量当前未被上游触碰） |
| multikey 日志前端 | `web/src/features/usage-logs/lib/format-multikey.test.ts`；`web/src/features/usage-logs/components/columns/common-logs-columns.tsx` 内多键列显示（上游本次未碰；若未来上游改它，此项升级进 B 类） |
| 价格表草稿徽标 | `web/src/features/system-settings/models/model-ratio-table-columns.tsx` 本地渲染（详见 B12；数据结构来自上游原生 model-pricing-snapshots） |
| 前端工程配置 | `web/.oxlintrc.json`、`web/rsbuild.config.ts` 改动、`web/scripts/` i18n/format 脚本 |
| 工具脚本 | `scripts/start-dev.ps1`、`scripts/release.bat`、`scripts/sync-script-tests.ps1`、`scripts/README.md` |
| 测试 | `service/codex_wham_usage_test.go`；`web/src/components/ui/dialog-content-width.test.ts`（DialogContent 宽度约定扫描）；随上游 vitest 化（2026-08-27） |
| 文档 | `docs/superpowers/**`、`docs/upstream-sync.md` 本手册 |

> 历史行记录：silent-batch 前端库（update-option-results）、theme.css 黑白灰预设、index.html 防闪烁脚本已于 2026-08-27 随 B4/B5 退役从本表移除。

## B 类：上游文件内的本地修改（覆盖后必须重放）

> 每项四要素：文件 / 内容 / grep 锚点 / 注意事项。「提取命令」可在任意轮次零漂移找回原始内容：`git show dev-backup-pre-sync:<path>`。

### B1 `setting/ratio_setting/model_ratio.go` — 【已退役 2026-08-27】

本地自建价格条目（babbage-002/davinci-002/babbage/ada + 8 个 360 系），上游从未拥有。2026-08-27 起主动放弃：整文件取上游。守护测试 `setting/ratio_setting/model_ratio_test.go` 一并删除；360 渠道自身的模型列表回归仍在 A 类 `relay/channel/ai360/constants_test.go`。反向断言见锚点索引。

### B4 silent-batch 批量保存特性 — 【已退役 2026-08-27】

主动放弃，调用面全部还原为上游形态：
- `types.ts`、`use-update-option.ts` 整文件取上游；
- `lib/update-option-results.ts(+test)` 删除（孤儿）；
- `ratio-settings-card.tsx` 两处 handler、`model-mutate-drawer.tsx` updates 循环还原上游写法（这两个文件仍保留 C1 剔除 / B10 注释，故继续留在 `$replayFiles`）。
代价说明：模型价格/分组/模型编辑多键保存会恢复上游"每键一次成功 toast"，中途失败不再自动失效缓存。原语义可随时从本节历史或 `dev-backup-pre-sync` 找回。

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

### B5 `web/src/styles/theme.css` — 黑白灰默认预设 — 【已退役 2026-08-27】

主动放弃：`theme.css` 与 `web/index.html`（防闪烁脚本）整文件取上游；`theme-presets.css` 本就与上游一致，零操作。站点恢复上游默认配色与明暗切换行为。反向断言见锚点索引。

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
| `web/src/features/system-settings/models/claude-settings-card.tsx` | `<SettingsPageFormActions` 内 `onSave={...}` 上方 ← `{/* eslint-disable-next-line react-hooks/refs */}`（JSX 注释版） |
| `web/src/features/system-settings/models/tiered-pricing-editor.tsx` | 两处：`setDraft(formatNumberDraft(value))` 与 `if (hasMediaPricing) setMediaOpen(true)` ← set-state-in-effect 注释 |
| `web/src/features/system-settings/models/upstream-ratio-sync.tsx` | `setChannelEndpoints((prev) => {` ← set-state-in-effect 注释 |
| `web/src/features/system-settings/models/conflict-confirm-dialog.tsx` | 对话框宽度：`className='max-w-4xl'` → `'w-[calc(100vw-2rem)] !max-w-4xl'`（样式修正，非 lint） |
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

### B12 `model-ratio-table-columns.tsx` — 价格表草稿徽标（2026-08-27 补录）

锚点：`isDraftChanged`、`Will be removed`。本地在 `buildModelRatioColumns` 的 name 列与价格明细列各渲染一个 Draft 徽标块（约 +30 行），数据来自上游原生 `model-pricing-snapshots.ts` 行结构（isDraftChanged/isDraftDeleted/draft 字段由 `model-ratio-visual-editor.tsx` 填充，均上游代码）。i18n 依赖 B11 键 2/3。某轮覆盖后重放：从 `dev-backup-pre-sync` 提取该文件 diff，两段徽标 JSX 按上游结构回插即可。

> 补录说明：此前手册漏登本项；2026-08-27 与上游比对全量差异时发现并归档。同步发现 `model-ratio-form.tsx` 约 151 行差异实为 C1 的管线移除（variant/unset 全套），已并入 C1 记录，非独立特性。

### B11 i18n 六键七语

锚点：`Updated; synced {{count}} active subscriptions`（en/zh 等 7 个 locale 文件 `.translation` 下各应有 5 个本地键）。键全集（en 原文）：
1. `Apply changes to existing subscriptions`
2. `Draft`
3. `Will be removed`
4. `Sync the new quota and reset period to active subscribers. Used quota is kept.`
5. `Updated; synced {{count}} active subscriptions`

七语译文以 `dev-backup-pre-sync` 分支的 locale 文件为源，注入脚本见计划任务 9（比较 backup 与当前文件、按字母序插回、保持 2 空格缩进与结尾换行）。键 1/4/5 服务于 B8；键 2/3 服务于 B12 草稿徽标；任何人新增 UI 文案时，对应键值必须当次补录（开发习惯条款）。
删除记录：原键 2 `Pricing changes saved to draft. Click "Save model prices" to apply.` 已于 2026-08-27 从七语全部移除（死键，无源码引用）。**locale 删键纪律**：sync-i18n 以"最富语言"自动选 base，只删单一语言会被反向回填——必须七个文件同时删净后再跑 `i18n:sync`，随后 grep 校验混淆品牌行未变。

## C 类：主动放弃的上游特性（每轮合并重新决策，防静默带回）

| # | 特性 | 放弃原因 | 涉及文件与本轮剔除动作 |
|---|---|---|---|
| C1 | unset-models 价格页签（默认 tab 与 variant 入口） | 与本地 silent-batch 流程冲突、产品上不需要该入口（2026-08-27 注：silent-batch 虽已退役，本剔除维持不变） | 取上游版后在 `web/src/features/system-settings/billing/section-registry.tsx` 检查 Model Pricing 与分组卡两处 `visibleTabs` 数组（约 114/127 行）不含 `'unset-models'`；在 `web/src/features/system-settings/models/ratio-settings-card.tsx` 从 RatioTabId 联合类型、tabLabels、renderTabContent 分支删去 unset-models 相关成员；在 `web/src/features/system-settings/models/model-ratio-form.tsx` 移除整套 `variant?: 'default' | 'unset'` 管线（props、isUnsetVariant 分支、enabled-models 查询与报错 toast、对应 UI 块，约 151 行）。具体代码见手册随附计划任务 6 |
| C2 | superpowers-zh 框架段（CLAUDE.md） | 2026-07-14 主动删除 | 若任何来源试图恢复 CLAUDE.md 该段落，拒绝并维持删除状态 |

## 锚点速查索引（第 4 步机械校验用；PowerShell 直接粘贴）

```powershell
$pairs = @(
  @('web/src/features/usage-logs/lib/format.ts','getMultiKeyIndex')
  @('web/src/features/usage-logs/lib/format-multikey.test.ts','getMultiKeyIndex')
  @('web/src/features/usage-logs/components/dialogs/details-dialog.tsx','multiKeyLabel')
  @('web/src/features/system-settings/models/model-ratio-table-columns.tsx','isDraftChanged')
  @('web/src/styles/theme-presets.css','data-theme-preset')
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

反向断言（C 类与已退役项确已缺席，全部应无命中；文件不存在时 Test-Path 返回 False 即 PASS）：

```powershell
$absent = @(
  @('web/src/features/system-settings/models/ratio-settings-card.tsx','unset-models')
  @('web/src/features/system-settings/billing/section-registry.tsx','unset-models')
  @('CLAUDE.md','superpowers-zh')
  @('setting/ratio_setting/model_ratio.go','360GPT_S2_V9')
  @('setting/ratio_setting/model_ratio.go','babbage-002')
  @('web/src/features/system-settings/types.ts','UpdateOptionMutationRequest')
  @('web/src/features/system-settings/hooks/use-update-option.ts','silent')
  @('web/src/styles/theme.css','oklch(0.13 0 0)')
  @('web/index.html','data-theme-preset')
)
foreach ($a in $absent) {
  if (-not (Test-Path $a[0])) { "PASS (file absent) $($a[0])"; continue }
  $hit = (Select-String -Path $a[0] -Pattern $a[1] -SimpleMatch | Measure-Object).Count
  if ($hit -eq 0) { "PASS (absent) $($a[0]) <- $($a[1])" } else { "FAIL 不应存在 $($a[0]) <- $($a[1])" }
}
# 已删除文件断言
foreach ($f in 'web/src/features/system-settings/lib/update-option-results.ts',
               'web/src/features/system-settings/lib/update-option-results.test.ts',
               'setting/ratio_setting/model_ratio_test.go') {
  if (Test-Path $f) { "FAIL 已退役文件又出现`t$f" } else { "PASS (deleted) $f" }
}
# 已退役取上游文件：与 upstream/main 必须零差异
foreach ($f in 'setting/ratio_setting/model_ratio.go',
               'web/src/features/system-settings/types.ts',
               'web/src/features/system-settings/hooks/use-update-option.ts',
               'web/src/styles/theme.css',
               'web/index.html') {
  $d = git diff --name-only upstream/main -- $f
  if ($d) { "FAIL 应等于上游`t$f" } else { "PASS (=upstream) $f" }
}
```

> 锚点索引变更记录（2026-08-27）：随 B1/B4/B5 退役移除 model_ratio/theme.css/types/use-update-option/update-option-results 五组正向锚点；新增 B12 草稿徽标锚点 `isDraftChanged` 与上述退役反向断言。`theme-presets.css` 的 data-theme-preset 为上游自带预设机制，保留正向校验。

## 手册维护纪律

1. 任何在 B/C 清单之外产生的本地新个性化（无论文件内条目还是整文件），合入当次必须同 commit 或紧随 commit 补录手册，并给 grep 锚点。
2. 每轮同步收尾时：更新 `$replayFiles` 与锚点索引为当次真实状态；把当次 merge-base 与 upstream 领先数写入本节下方「轮次记录」。
3. 「提取命令」惯例：历史真相永远在 `dev-backup-pre-sync`，手册描述原则，提取命令交付字节。

## 轮次记录

| 日期 | merge-base | upstream 领先 | 备注 |
|---|---|---|---|
| 2026-08-26 | bc14c18f6024e79cba1c08d02cd007796e12d668 | 83 commits | 手册首轮实战；封面考古结论：嵌套计费属共享基底；B 清单定稿 B1-B11 |
| 2026-08-27 | bc14c18f（同轮收尾，未 push） | 0（83 已全部并入） | 门槛收尾：format:check 5 个上游带入文件按 oxfmt 归一（剥保护头流程）；三个本地 node:test 测试迁 vitest（dialog-content-width / update-option-results / format-multikey）；漂移脚本第 2 段 PS 判定勘误（见脚本下方注记） |
| 2026-08-27 | —（非同步轮·退役专项） | — | 退役 B1/B4/B5：相关文件取上游或还原调用面，删 model_ratio_test.go 与孤儿 update-option-results(+test)；B11 键2 七语清理，实测发现 sync-i18n「最富语言选 base」对删键不友好——必须七语同时删净再跑 sync（纪律已写入 B11）；借机全量比对上游归档手册外差异：C1 补录 model-ratio-form 管线移除、B10 补列 4 文件、新增 B12 草稿徽标 |
