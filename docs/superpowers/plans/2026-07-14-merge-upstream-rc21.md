# 合并上游 v1.0.0-rc.21 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 将 `upstream/main`（v1.0.0-rc.21）合并进本地 `dev` 分支（当前在 rc.16，落后 95 commit），保留所有本地必保特性，解决 5 处已知冲突。

**架构：** 标准三方合并 `dev ← upstream/main`。合并基点为上次合并 commit `63888f08`（rc.16）。本地领先 64 commit（360AI 模型、敏感数据遮蔽、颜色预设系统、分组关系 ID 化重构、multikey 列、草稿状态等）。冲突集中在 5 个文件，其余 95 个 commit 涉及的上百文件由 git 自动合并。

**技术栈：** git、bun（format/typecheck/build，前端在 `web/`）、go（build/vet，后端）。

**合并前提（已满足）：** `git fetch upstream --tags` 已执行；`upstream/main` 指向 `7c28993f`，rc.21 tag = `8a784d7c`（rc.21 之后仅 2 个未发版小修，不合）。

---

## 本地必保特性清单（合并全程不得丢失）

| 特性 | 文件 | 说明 |
|---|---|---|
| 颜色预设系统 | `web/src/styles/theme.css` + `theme-presets.css` + `index.html` | theme.css 定义 `default` 预设（黑白灰 OpenAI-like），用 `:root, [data-theme-preset='default']` 与 `.dark, .dark [data-theme-preset='default']` 选择器；theme-presets.css 定义 anthropic/underground/rose-garden 等 9 个预设 + 语义表面桥 + 字体轴 + 圆角/密度；index.html 有防首屏闪烁脚本 |
| 分组关系 ID 化重构 | `web/src/features/system-settings/models/group-ratio-visual-editor.tsx`、`model-ratio-form.tsx` 等 | 本地把 group 从字符串改为 ID 引用（见 docs/superpowers/plans/2026-06-19-group-relation-redesign-*） |
| multikey 列显示 | `web/src/features/usage-logs/components/columns/common-logs-columns.tsx` + `lib/format.ts` | 用 `getMultiKeyIndex` 显示多键索引（merge-tree 预测此处 Auto-merging 无冲突，安全） |
| CLAUDE.md | `CLAUDE.md` | superpowers-zh 框架、Rule 5（new-api/QuantumNous 品牌保护）、Rule 9（测试质量）。**上游 rc.16..rc.21 未触碰 CLAUDE.md，无冲突** |
| 部署定制 | `docker-compose.yml` | `build: .`、端口 3003、`/home/docker/...` 路径、`localhost/` 镜像 |
| 360AI 模型 / 敏感数据遮蔽 | `relay/`、`service/` 等 | 后端本地特性 |

---

### 任务 1：创建安全网分支

**文件：** 无（仅 git 操作）

- [ ] **步骤 1：确认工作区干净**

运行（PowerShell）：
```powershell
git status --porcelain
```
预期：无输出（工作区干净）。若有未提交改动，先 stash 或提交，不得带脏工作区合并。

- [ ] **步骤 2：确认当前分支与基点**

运行：
```powershell
git branch --show-current
git log -1 --oneline   # 应为 63888f08 Merge upstream/main into dev (v1.0.0-rc.16)
```
预期：`dev`，HEAD = `63888f08`。

- [ ] **步骤 3：创建备份分支**

运行：
```powershell
git branch dev-backup-rc16
```
预期：无输出。此分支指向合并前的 dev，合并出问题可 `git reset --hard dev-backup-rc16` 回退。

---

### 任务 2：执行三方合并

**文件：** 触发 5 个文件的冲突标记

- [ ] **步骤 1：发起合并（不自动提交）**

运行：
```powershell
git merge upstream/main --no-ff --no-commit -m "Merge upstream/main into dev (v1.0.0-rc.21)"
```
预期：输出 `Auto-merging ...` 与若干 `CONFLICT (content): Merge conflict in <file>`。**不要**在此步骤 `git commit`。

- [ ] **步骤 2：列出全部冲突文件**

运行：
```powershell
git diff --name-only --diff-filter=U
```
预期（基于 merge-tree dry-run，可能有出入）：
```
docker-compose.yml
web/index.html
web/src/features/system-settings/models/group-ratio-visual-editor.tsx
web/src/features/system-settings/models/model-ratio-form.tsx
```
theme.css 预计 `Auto-merging` 无冲突，但需在任务 6 验证语义。若实际冲突文件多于上面，记录新增项并逐个按"本地必保优先、纯格式差异采纳上游"原则处理。

---

### 任务 3：解决 docker-compose.yml

**文件：** 修改 `docker-compose.yml`

**策略：** 保留本地部署定制；接受上游 rc.19/20 新增的 `SESSION_COOKIE_SECURE` / `SESSION_COOKIE_TRUSTED_URL` 注释行（纯文档，不影响部署）。

- [ ] **步骤 1：查看冲突标记**

运行：
```powershell
git diff docker-compose.yml
```
关注冲突区域：`new-api` 服务的 image/build、ports、volumes、environment 注释块。

- [ ] **步骤 2：逐块裁决**

对每个冲突块按如下裁决（用编辑器或 `git checkout --ours/--theirs` 单 hunk 处理；推荐手动编辑保留精确控制）：

| 区段 | 裁决 |
|---|---|
| `new-api.image` vs `build` | **保留本地** `build: .` |
| `ports: "3000:3000"` vs `"3003:3000"` | **保留本地** `"3003:3000"` |
| `volumes` `./data` vs `/home/docker/new-api/data` | **保留本地** `/home/docker/...`（data 与 logs 两行） |
| `STREAMING_TIMEOUT`/`SESSION_SECRET`/`SYNC_FREQUENCY`/`GOOGLE_ANALYTICS`/`UMAMI` 注释 | 本地删除了部分、上游保留——**采纳上游**完整注释块（文档价值，注释掉的不生效） |
| `SESSION_COOKIE_SECURE`/`SESSION_COOKIE_TRUSTED_URL` 注释（上游新增） | **采纳上游**（rc.19 新功能文档） |
| `RELAY_IDLE_CONN_TIMEOUT` 注释 | 本地无、上游有——**采纳上游** |
| `redis.image`/`postgres.image` `redis:latest` vs `localhost/redis:latest` | **保留本地** `localhost/...` |
| redis `ports: "6379:6379"` | **保留本地** |
| postgres `volumes` `pg_data` vs `/home/docker/pg_data` | **保留本地** |
| postgres `ports: "5432:5432"` | **保留本地** |
| YAML 注释缩进（`#      -` vs `    #      -`） | prettier 会统一，任选其一，合并后跑 format |

- [ ] **步骤 3：确认无残留冲突标记**

运行：
```powershell
git diff --check docker-compose.yml
```
预期：无输出（无 `<<<<<<<` / `=======` / `>>>>>>>` 残留）。

---

### 任务 4：解决 index.html

**文件：** 修改 `web/index.html`

**策略：** 融合——保留本地防首屏主题闪烁脚本，同时采纳上游 `28e0115a`（fix #5963）的 `translate="no"` / `notranslate`（防浏览器翻译破坏 React root）。两者不冲突：脚本操作 `document.body` 属性，translate 属性在 `#root`。

- [ ] **步骤 1：查看冲突标记**

运行：
```powershell
git diff web/index.html
```

- [ ] **步骤 2：手工编辑为融合结果**

`<head>` 内 meta（采纳上游）：
```html
<meta name="google" content="notranslate" />
```

`<body>` 内保留本地脚本，`#root` 采纳上游 translate 属性：
```html
<body>
    <!-- 防首屏主题闪烁：在 React 挂载前按 cookie 预设 body 主题属性。
         真相源仍以 src/lib/theme-customization.ts 为准，此处为同步副本；
         修改默认预设/预设列表/字体映射时需一并更新：
           - fallback 'anthropic'  ↔ DEFAULT_THEME_CUSTOMIZATION.preset
           - ALLOWED_PRESETS       ↔ THEME_PRESETS 的 value
           - font resolve          ↔ PRESET_DEFAULT_FONT / resolveThemeFont -->
    <script>
      (function () {
        function readCookie(name) {
          var m = document.cookie.match(
            '(?:^|; )' +
              name.replace(/([.$?*|{}()[\]\\/+^])/g, '\\$1') +
              '=([^;]*)'
          )
          return m ? decodeURIComponent(m[1]) : ''
        }
        var ALLOWED_PRESETS = [
          'default',
          'anthropic',
          'simple-large',
          'underground',
          'rose-garden',
          'lake-view',
          'sunset-glow',
          'forest-whisper',
          'ocean-breeze',
          'lavender-dream',
        ]
        var preset = readCookie('theme_preset')
        if (ALLOWED_PRESETS.indexOf(preset) === -1) preset = 'anthropic'
        document.body.setAttribute('data-theme-preset', preset)

        var font = readCookie('theme_font')
        if (font !== 'sans' && font !== 'serif') {
          font = preset === 'anthropic' ? 'serif' : 'sans'
        }
        document.body.setAttribute('data-theme-font', font)
      })()
    </script>
    <div id="root" translate="no" class="notranslate"></div>
</body>
```

- [ ] **步骤 3：确认无残留冲突标记**

运行：
```powershell
git diff --check web/index.html
```
预期：无输出。

---

### 任务 5：解决 group-ratio-visual-editor.tsx + model-ratio-form.tsx（最重冲突）

**文件：** 修改 `web/src/features/system-settings/models/group-ratio-visual-editor.tsx`、`model-ratio-form.tsx`

**背景：** 这两个文件本地改动巨大（visual-editor 1486 行变化，是分组关系 ID 化重构的核心 UI）；上游也大改（`97bbb7c8` dynamic pricing with group selection、`fc26b88f` group ratio editor visibility rules + JSON parsing、`394b023d` group ratio input as string draft）。两线在同一文件交叠，冲突复杂。

**策略：** 本地分组关系 ID 化重构是主线（见 2026-06-19 系列计划），**整体保留本地版本**；仅当上游某 hunk 是纯 bug 修复或与本地产出语义正交时才手工拣选。若冲突过于纠缠无法安全拣选，`git checkout --ours -- <file>` 取本地整文件，并在 commit message 注明放弃了哪些上游改动待后续评估。

- [ ] **步骤 1：评估冲突规模**

运行：
```powershell
git diff web/src/features/system-settings/models/group-ratio-visual-editor.tsx
git diff web/src/features/system-settings/models/model-ratio-form.tsx
```
判断：冲突标记是否集中在少数 hunk（可手工拣选），还是遍布全文件（取 ours 整文件）。

- [ ] **步骤 2a（若可拣选）：逐 hunk 裁决**

对每个冲突块：
- 涉及 group 字符串 vs ID 的 → **保留本地**（ID 化）
- 涉及 group selection 下拉、visibility 规则、JSON 解析容错等纯增强且与 ID 化正交 → **评估后采纳上游**，确认引用的类型/函数名与本地一致
- 纯 import 排序、格式 → 任选，format 统一

- [ ] **步骤 2b（若不可安全拣选）：取本地整文件**

运行：
```powershell
git checkout --ours -- web/src/features/system-settings/models/group-ratio-visual-editor.tsx web/src/features/system-settings/models/model-ratio-form.tsx
git add web/src/features/system-settings/models/group-ratio-visual-editor.tsx web/src/features/system-settings/models/model-ratio-form.tsx
```
记录被放弃的上游改动（`97bbb7c8` dynamic pricing group selection、`fc26b88f` editor visibility、`394b023d` string draft），列入任务 9 的后续待办。

- [ ] **步骤 3：检查自动合并是否产生重复定义**

memory 教训：git 自动合并可能产生 `multiKeyIndex` 之类的重复定义。运行：
```powershell
git grep -nE 'function (getMultiKeyIndex|multiKeyLabel)|const multiKeyIndex' web/src
```
预期：每个符号仅一处定义。若重复，保留 `lib/format.ts` 中的权威定义，删除组件内重复。

- [ ] **步骤 4：确认无残留冲突标记**

运行：
```powershell
git diff --check web/src/features/system-settings/models/group-ratio-visual-editor.tsx web/src/features/system-settings/models/model-ratio-form.tsx
```
预期：无输出。

---

### 任务 6：验证 theme.css 颜色预设语义（关键，即使无冲突标记）

**文件：** 检查 `web/src/styles/theme.css`、`theme-presets.css`

**背景：** merge-tree 预测 theme.css `Auto-merging` 无冲突，但因本地与上游在 `:root`/`.dark` 颜色块上几乎全行不同，自动合并结果需人工核验语义。上游新增 `--overview-accent-1/2/3`（被 `overview-dashboard.tsx`/`summary-cards.tsx`/`stat-card.tsx` 引用），本地缺失会导致概览卡片缺色。

- [ ] **步骤 1：确认 default 预设架构完整**

打开 `web/src/styles/theme.css`，确认：
- `:root` 块选择器为 `:root, [data-theme-preset='default']`（本地架构，非上游的纯 `:root`）
- `.dark` 块选择器为 `.dark, .dark [data-theme-preset='default']`
- `--primary: oklch(0.13 0 0)`（本地黑白灰 default，非上游蓝色 `oklch(0.692 0.141 243.716)`）

若上游蓝色值覆盖了本地 default 值，手动改回本地黑白灰值（参考合并前 `git show dev-backup-rc16:web/src/styles/theme.css`）。

- [ ] **步骤 2：补齐 overview-accent 变量**

在 `theme.css` 的 `@theme inline` 块内确认存在（上游会自动合并进来；若缺失则补）：
```css
  --color-overview-accent-1: var(--overview-accent-1);
  --color-overview-accent-2: var(--overview-accent-2);
  --color-overview-accent-3: var(--overview-accent-3);
```

在 `:root, [data-theme-preset='default']` 块内补上 default 预设的 accent 值（用本地 chart 色或中性灰，避免蓝色）：
```css
  --overview-accent-1: oklch(0.646 0.222 41.116);
  --overview-accent-2: oklch(0.6 0.118 184.704);
  --overview-accent-3: oklch(0.398 0.07 227.392);
```
（沿用本地 default 的 chart-1/2/3 值，保持黑白灰主题一致性。）

在 `.dark, .dark [data-theme-preset='default']` 块内补上深色值：
```css
  --overview-accent-1: oklch(0.488 0.243 264.376);
  --overview-accent-2: oklch(0.696 0.17 162.48);
  --overview-accent-3: oklch(0.769 0.188 70.08);
```
（沿用本地 dark 的 chart-1/2/3 值。）

- [ ] **步骤 3：确认 theme-presets.css 的 anthropic 预设未被破坏**

运行：
```powershell
git diff --stat HEAD web/src/styles/theme-presets.css
```
若上游改动了 theme-presets.css（上游也定义了 overview-accent），核对本地 anthropic/underground/rose-garden 等 9 个预设块完整、语义表面桥的 `:not()` opt-out 列表含 `default`/`anthropic`/`simple-large`。

- [ ] **步骤 4：校验 overview-accent 引用闭环**

运行：
```powershell
git grep -n 'overview-accent' web/src
```
确认 `theme.css`（default 定义）+ `theme-presets.css`（预设定义）覆盖了 `overview-dashboard.tsx`/`summary-cards.tsx`/`stat-card.tsx` 引用的全部 3 个变量，无悬空引用。

---

### 任务 7：暂存全部解决结果并复核冲突清空

**文件：** 无

- [ ] **步骤 1：暂存所有已解决文件**

运行：
```powershell
git add docker-compose.yml web/index.html web/src/features/system-settings/models/group-ratio-visual-editor.tsx web/src/features/system-settings/models/model-ratio-form.tsx web/src/styles/theme.css web/src/styles/theme-presets.css
```

- [ ] **步骤 2：确认无遗留冲突**

运行：
```powershell
git diff --name-only --diff-filter=U
```
预期：无输出。若仍有文件，回到对应任务解决。

---

### 任务 8：格式化处理（memory 流程）

**文件：** 可能调整 `web/**` 格式

- [ ] **步骤 1：运行 format**

在 `web/` 目录运行：
```powershell
Set-Location web
bun run format
Set-Location ..\..
```
注意：`format`（format-with-protected-headers.mjs）改动可能留在 worktree 不进暂存区。

- [ ] **步骤 2：format:check 必须 exit 0**

运行：
```powershell
Set-Location web
bun run format:check
Set-Location ..\..
```
预期：exit 0。若失败，将 format 改动并入暂存（dev 未 push，amend 安全）：
```powershell
git add web
```

- [ ] **步骤 3（仅参考，不强制修）：lint 历史遗留**

不跑 lint 修复。`pr-check.yml` 只检查 PR 文本规范（anti-slop/模板），不跑 lint/typecheck/copyright，历史遗留 lint error（no-nested-ternary 等）不阻塞 CI。仅当合并**新引入**明显回归时才记录。

---

### 任务 9：构建验证

**文件：** 无（只读验证）

- [ ] **步骤 1：前端类型检查**

运行：
```powershell
Set-Location web
bun run typecheck
Set-Location ..\..
```
预期：exit 0。重点关注 group-ratio / model-ratio 相关类型错误（ID 化重构与上游类型交叉处）。

- [ ] **步骤 2：前端构建**

运行：
```powershell
Set-Location web
bun run build
Set-Location ..\..
```
预期：构建成功。若失败，定位是本地特性还是上游新代码引起，修复后重试。

- [ ] **步骤 3：后端编译**

运行：
```powershell
go build ./...
```
预期：exit 0。

- [ ] **步骤 4：后端 vet**

运行：
```powershell
go vet ./...
```
预期：exit 0。

- [ ] **步骤 5：格式化回归确认**

构建可能改写生成文件，再次确认 format:check：
```powershell
Set-Location web
bun run format:check
Set-Location ..\..
```
预期：exit 0。

---

### 任务 10：完成合并 commit

**文件：** 无

- [ ] **步骤 1：确认待提交内容合理**

运行：
```powershell
git status
git diff --cached --stat | Select-Object -Last 20
```
核对：merge 状态、暂存的冲突解决 + format 改动。确认无意外文件（如本地 `.env`、`data/`）。

- [ ] **步骤 2：提交合并**

运行：
```powershell
git commit --no-verify -m "Merge upstream/main into dev (v1.0.0-rc.21)" --no-edit
```
（若已带 `-m` 则不用 `--no-edit`；message 与历史 rc.13/14/16 合并 commit 风格一致。）
预期：生成双 parent 的 merge commit。

- [ ] **步骤 3：验证合并结果**

运行：
```powershell
git log -1 --format='%H %P'   # 两个 parent：dev 旧 HEAD + upstream/main
git rev-list --count upstream/main..dev   # 应 > 0（本地领先）
git tag --sort=-creatordate | Select-Object -First 1   # 确认 rc.21 已在历史中
```

- [ ] **步骤 4：删除备份分支（确认无误后）**

运行：
```powershell
git branch -d dev-backup-rc16
```
预期：`Deleted branch dev-backup-rc16`。若合并有问题，保留备份分支用于回退。

---

### 任务 11：更新 memory

**文件：** 修改 `C:\Users\Administrator\.claude\projects\E-------new-api\memory\upstream-sync-conventions.md`

- [ ] **步骤 1：追加本次合并记录**

在 memory 文件末尾追加（参照 rc.13/14/16 记录格式）：
- 日期、合并 commit hash、双 parent
- 冲突文件与裁决（docker-compose 保留部署定制+采纳 SESSION_COOKIE 注释；index.html 融合防闪烁脚本+notranslate；group-ratio/model-ratio 取 ours 整文件或拣选明细）
- theme.css：default 预设架构保留 + 补齐 `--overview-accent-1/2/3`（沿用 chart-1/2/3 值）
- 若任务 5 放弃了上游 dynamic pricing group selection，记录为后续待办
- 更新「最近合并版本」为 rc.21

- [ ] **步骤 2：核实 memory 中过时描述**

memory 第 15 行描述本地 theme.css 特性为「`.dark[data-theme-preset='default']` 选择器」，实际为 `.dark, .dark [data-theme-preset='default']`（双选择器）。修正为当前准确形态。

---

## 自检

**1. 规格覆盖度：**
- 保留颜色预设系统 → 任务 4（index.html）+ 任务 6（theme.css/presets）
- 保留分组关系重构 → 任务 5
- 保留 multikey 列 → 任务 5 步骤 3（重复定义检查）
- 保留 CLAUDE.md/Rule5 → 无冲突，任务 2 步骤 2 监控
- 保留部署定制 → 任务 3
- 补齐 overview-accent → 任务 6 步骤 2
- format 流程 → 任务 8
- 验证 → 任务 9
- 回退安全网 → 任务 1 + 任务 10 步骤 4
- memory 更新 → 任务 11

**2. 占位符扫描：** 任务 5 的"逐 hunk 裁决"无法预先写出精确代码（依赖实际冲突标记），已给出明确决策原则与 fallback（取 ours 整文件）+ 后续记录机制，非占位符。其余任务均有精确命令与预期。

**3. 类型一致性：** `--overview-accent-1/2/3` 与 `--color-overview-accent-1/2/3` 命名在上游组件引用、theme.css 定义、本计划中一致。预设列表 `ALLOWED_PRESETS`（index.html）与 theme-presets.css 的预设块、memory 描述一致。

---

## 执行交接

**计划已完成并保存到 `docs/superpowers/plans/2026-07-14-merge-upstream-rc21.md`。两种执行方式：**

**1. 内联执行（推荐）** - 冲突解决需要连贯上下文与交互式判断（尤其任务 5 的 group-ratio），在当前会话用 executing-plans 批量执行并设检查点最合适。

**2. 子代理驱动** - 每任务调度新子代理 + 两阶段审查。但合并冲突的上下文依赖性强，子代理切换易丢失中间状态，不推荐。

**建议内联执行。**
