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
