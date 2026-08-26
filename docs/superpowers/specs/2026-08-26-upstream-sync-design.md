# 上游全覆盖同步 + 个性化清单重放设计

取代 `2026-06-04-fork-sync-workflow-design.md`（其 no-commit merge 机制保留为本设计中流程第 2~3 步的执行形态）。

## 背景

- 本仓库是 QuantumNous/new-api 的 fork（origin = yangshare/new-api，本地 tag `v1.2.x-dockeronly`）。
- 上游版本号为 `v1.0.0-rc.x`，数字低于本地 tag 但功能领先--同步以 commit 差距为准。
- 历次合并的教训（见项目记忆 `merge-theirs-pitfall`）：
  1. `git merge -X theirs` 只对**冲突行**取上游；双方改**不同行**时 git 自动三方合并产生无冲突标记的"混血文件"，接口错位、编译期才暴露。
  2. 逐次现场考古（merge-base diff 判断"本地零改动残留" vs "真实个性化"）成本高且重复劳动。
- 本地真实个性化点是个位数（~7 个文件级 + 若干文件内条目），远小于每次合并的上游变更量。

## 核心模式

**基底跟随上游 + 个性化清单重放**：

> 每次同步 = 对"双方都改过的上游文件"整文件取上游版（真正意义的全覆盖，不信任何自动合并）→ 按一份文档化的清单把个性化点逐项重放回去 → 用机械校验（锚点 grep + 漂移 diff）确认无遗漏。

个性化点少数 + 上游变更量大时，该模式把"每轮现场考古"变成"每轮机械重放"，成本恒定。

## 两个核心风险与对策

| 风险 | 对策 |
|---|---|
| 自动合并产生混血文件 | 全覆盖不依赖 `-X theirs`；对所有"双方都改"文件逐个 `git checkout upstream/main -- <file>` 整文件取上游，一视同仁 |
| 清单漂移（本地新增个性化未入清单，下次覆盖无声丢失） | 双保险：① 锚点校验--清单每项带 grep 锚点，重放后逐项验证存在；② 漂移检测--`git diff dev-backup-pre-sync..dev` 中排除上游自身变化后，剩余差异必须能对应到清单某项，清单外差异 = 补录或明确放弃 |

## 《上游同步手册》设计（`docs/upstream-sync.md`）

流程与清单合一的单一事实源。清单分三类：

### A 类：本地独有文件（上游不存在对应文件）

merge 天然保留，不参与覆盖。列出仅为了：备份/回滚时防误删、新会话快速了解本地特性面。
示例：`relay/channel/ai360/`、subscription 相关文件、本地 docs。

### B 类：上游文件内的本地修改（覆盖后需重放）

每项必须包含：文件路径、修改内容（可直接复制的代码块/条目）、**grep 锚点**、重放注意事项。
已识别项（本轮初始版）：

| # | 文件 | 个性化内容 | 锚点 |
|---|---|---|---|
| B1 | `setting/ratio_setting/model_ratio.go` | 本地模型价格条目：`babbage-002`/`davinci-002`/`babbage`/`ada` + 8 个 360 系条目 | `360GPT_S2_V9` |
| B2 | `web/src/features/usage-logs/lib/format.ts` | `getMultiKeyIndex`（含 `web/src/lib/format.ts` 与 format-multikey.test.ts 配套） | `getMultiKeyIndex` |
| B3 | `web/src/features/channels/.../common-logs-columns.tsx`（usage-logs columns） | multiKeyLabel/multiKeyTitle 多键索引显示 | `multiKeyLabel` |
| B4 | `web/src/features/system-settings/models/ratio-settings-card.tsx` + `billing/section-registry.tsx` + `model-ratio-form.tsx`/`group-ratio-visual-editor.tsx` | 嵌套计费（GroupGroupRatio + baseRatioByName）；**放弃**上游 unset-models tab/variant | `baseRatioByName` |
| B5 | `web/src/styles/theme.css`（+ theme-presets.css、index.html 防闪烁脚本 fallback） | 黑白灰默认预设：`--primary: oklch(0.13 0 0)` 等 | `oklch(0.13 0 0)` |
| B6 | `CLAUDE.md` | Rule 5 保护信息、Rule 9 测试质量；superpowers-zh 段已删勿恢复 | `Rule 9` |
| B7 | `Dockerfile`、`.gitignore`、`.github/workflows/{release,electron-build}.yml` | docker-only 构建定制 | 视具体定制逐项核对 |
| B8 | `model/subscription.go`、`controller/subscription.go` | 本地"计划变更同步到存量订阅"特性（`SyncPlanSubscriptionsTx` + `SubscriptionPlanSyncResult`），与上游 subscription-expiry 修复并存时手工融合 | `SyncPlanSubscriptionsTx` |

B 类清单**以本轮考古结论为初始版**，此后每次本地新增个性化必须同步补录（写入开发习惯）。

### C 类：主动放弃的上游特性

每项记录：特性名、放弃原因、涉及文件。每次合并时重新决策是否引入，防止 git 自动恢复被静默带上。
已识别项：unset-models tab（B4 内联）、superpowers-zh 框架段（B6 内联）。

## 五步同步流程（每轮固定执行）

1. **备份**：`git branch dev-backup-pre-sync`（工作区必须干净）。
2. **合并**：`git merge --no-commit --no-ff upstream/main`。冲突解决时，对**所有双方都改的文件**（当次用 merge-base 现算，不照抄历史清单）整文件取上游：`git checkout upstream/main -- <file>`。A 类本地独有文件不在冲突集内，天然保留。
3. **重放**：按 B 类清单逐项把个性化内容改回。涉及与上游新增逻辑交织的（如 B8 订阅 vs 上游订阅加固），手工融合。
4. **锚点校验**：逐项 grep 锚点验证存在。失败即重放有漏，回到第 3 步。
5. **漂移检测**：`git diff dev-backup-pre-sync..dev`，逐块归因：要么对应清单某项，要么属于上游变更；出现清单外的本地差异丢失 = 清单遗漏 → 补录该个性化（或明确决定放弃并记入 C 类）。

## 验证门槛（第 5 步之后，提交前）

按序全部通过才允许 commit：

1. `go build ./...`
2. `bun run typecheck`（web/）
3. `bun run build`（web/）
4. 定向测试：quota/billing（int32->int64 弃用压计费代码）、ratio_setting、ai360、subscription
5. `bun run format:check`（只读安全；**不要**跑 `format --write`，历史上曾误改 CLAUDE.md）
6. `git diff CLAUDE.md`、`git diff -- web/src/styles/theme.css` 确认保护文件未被误动

## 本轮范围（2026-08-26）

- 上游 83 commit 全量合入（含 relaykit 模块抽取 368 文件、int32 弃用 35 文件、计费/安全修复、功能新增）。
- 已侦察确认：双方都改的文件仅 30 个，其中 ~7 项真实个性化（即 B 类初始清单）；relaykit 重构与本地改动几乎无重叠（本地 relay 层只动过 ai360，上游未碰）；theme.css / CLAUDE.md 本轮上游未改，重放零风险。
- 执行顺序：先写 `docs/upstream-sync.md`（B 类清单从 merge-base diff 考古提炼）→ 用它执行本轮同步 → 实战验证流程本身。

## 回滚

dev 未推送远端新状态前：`git reset --hard dev-backup-pre-sync`。合并 commit 后发现问题：`git reset --hard dev-backup-pre-sync`（未 push 时安全）或按文件粒度 `git checkout dev-backup-pre-sync -- <file>`。

## 文件清单

| 文件 | 用途 |
|---|---|
| `docs/upstream-sync.md` | 上游同步手册：A/B/C 清单 + 五步流程 + 验证门槛（单一事实源） |
| `docs/superpowers/specs/2026-08-26-upstream-sync-design.md` | 本设计文档 |
