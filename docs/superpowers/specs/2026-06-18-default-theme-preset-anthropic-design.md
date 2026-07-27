<!--
Copyright (C) 2023-2026 QuantumNous

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.
-->

# 颜色预设默认值改为 Anthropic — 设计规格

- 日期：2026-06-18
- 范围：`web/` 前端主题系统
- 目标前端：default 主题（React 19）

## 1. 背景与目标

当前颜色预设（color preset）的默认值是 `default`（中性黑白）。需求：将开箱默认预设改为 `anthropic`，使每个**未设置过主题偏好**的用户首次进入即看到 Anthropic 主题（暖奶油色画布 + 编辑型衬线字体）。

用户决策（已确认）：
- **老用户处理**：仅新用户/未设置过的用户默认 Anthropic；已在 cookie 中记录过主题偏好的老用户保留其原选择。
- **实现方案**：方案 A+（provider 始终写属性 + default 显式 CSS 块 + `index.html` 内联防闪脚本），零 FOUC、不动任何 CSS 变量值、风险最低。

## 2. 当前架构与关键约束

主题定制状态由 `context/theme-customization-provider.tsx` 管理，通过 cookie 持久化，通过 `<body>` 上的 `data-theme-preset` / `data-theme-font` / `data-theme-radius` / `data-theme-scale` / `data-theme-content-layout` 属性驱动 CSS 变量级联。

### 关键约束：`default` 预设被"焊死"为无属性回退

- `styles/theme.css` 的 `:root`（浅色）与 `.dark`（暗色）块**就是** `default` 预设的变量定义。`default` 预设在 `theme-presets.css` 中**没有**自己的 `[data-theme-preset='default']` 块。
- provider 在 preset 等于默认值时**移除** `data-theme-preset` 属性（`theme-customization-provider.tsx:140`），使样式回落到 `:root`（即 default）。

**因此直接把默认值改成 `'anthropic'` 会产生 bug**：默认用户（cookie 不存在）→ preset = `'anthropic'` = 默认值 → 移除属性 → 回落 `:root` → 显示的仍是黑白 default，而非 anthropic。必须同步调整属性写入逻辑，并让 `default` 预设有显式 CSS 块。

### CSS import 顺序

`styles/index.css` 第 30–31 行：`theme.css` 在前、`theme-presets.css` 在后。`<body>` 同一时刻只持有一个 `data-theme-preset` 值，故 default 显式块与各命名预设块不会在同一元素上冲突。

## 3. 方案决策（A+）

只改 `preset` 这一个轴的 DOM 写入逻辑。其余三个轴在 anthropic 成为默认时天然正确：

- **font**：provider 已在 `resolveThemeFont()` 后始终写入属性（`:150-152`），不受"等于默认值移除属性"影响。
- **radius**：等于默认值时移除属性，回落到**当前预设块**自带的 `--radius`（anthropic 块定义了 `--radius: 0.625rem`），正确。
- **scale**：等于默认值时移除属性，回落 `:root` 默认尺寸，正确。

只有 `preset` 的"等于默认值→移除属性"会出错（移除后回落 `:root` = default）。

`index.html` 加内联脚本在首屏（JS 执行前）预设 `data-theme-preset` 与 `data-theme-font`，消除首屏 FOUC（颜色 + 字体）。

## 4. 详细改动

### 4.1 `web/src/lib/theme-customization.ts`

`DEFAULT_THEME_CUSTOMIZATION.preset` 由 `'default'` 改为 `'anthropic'`：

```ts
export const DEFAULT_THEME_CUSTOMIZATION: ThemeCustomization = {
  preset: 'anthropic',
  font: 'default',
  radius: 'default',
  scale: 'default',
  contentLayout: 'full',
}
```

`PRESET_DEFAULT_FONT`（`default → 'sans'`、`anthropic → 'serif'`）与 `resolveThemeFont` 不变。

### 4.2 `web/src/context/theme-customization-provider.tsx`

preset 的 `useEffect`（当前 137–142 行）改为始终写入属性，删除"等于默认值→移除属性"的三元：

```ts
useEffect(() => {
  applyAttribute('data-theme-preset', preset)
}, [preset])
```

`setPreset`（172–179）的 cookie 逻辑保持不变（等于默认值仍 `removeCookie`，节省 cookie）。font / radius / scale 的 effect 与 cookie 逻辑均不变。

### 4.3 `web/src/styles/theme.css`

让 `default` 预设有显式块（复用现有变量定义，不搬值）：

- 第 93 行 `:root {` → `:root, [data-theme-preset='default'] {`
- 第 147 行 `.dark {` → `.dark, .dark [data-theme-preset='default'] {`

`:root` 中的非颜色 token（`--radius`、`--app-header-height`、`--app-rev`、`--font-body`）随之在显式 default 块上重复声明，值相同，无副作用。

### 4.4 `web/index.html`

在 `<body>` 内、`<div id="root">` 之前插入内联脚本，首屏预设属性（此脚本执行时 `document.body` 已可用）：

```html
<body>
  <script>
    // 防首屏主题闪烁：在 React 挂载前根据 cookie 预设 body 主题属性。
    // 真相源仍以 lib/theme-customization.ts 为准；此处为同步副本，
    // 修改默认预设/预设列表/字体映射时需一并更新：
    //   - fallback 'anthropic'      ↔ DEFAULT_THEME_CUSTOMIZATION.preset
    //   - allowed 列表              ↔ THEME_PRESETS 的 value
    //   - font resolve (anthropic→serif, 其余→sans) ↔ PRESET_DEFAULT_FONT / resolveThemeFont
    (function () {
      function readCookie(name) {
        var m = document.cookie.match(
          '(?:^|; )' + name.replace(/([.$?*|{}()[\]\\/+^])/g, '\\$1') + '=([^;]*)'
        )
        return m ? decodeURIComponent(m[1]) : ''
      }
      var ALLOWED_PRESETS = [
        'default', 'anthropic', 'simple-large', 'underground', 'rose-garden',
        'lake-view', 'sunset-glow', 'forest-whisper', 'ocean-breeze', 'lavender-dream',
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
  <div id="root"></div>
</body>
```

说明：radius / scale 无需内联处理——radius 由 preset 块的 `--radius` 自动决定；scale 默认即 `:root` 尺寸。

## 5. 边界与不在范围（YAGNI）

- dark mode 首屏 FOUC（既有问题，与 preset 无关）不在本次范围。
- 不删除 `default` 预设，保留为可选项。
- 不改动 radius / scale / contentLayout 的 effect 与 cookie 逻辑。

## 6. 双源同步点

`index.html` 内联脚本与 `lib/theme-customization.ts` 存在三处需同步的硬编码，已在脚本注释中标注：fallback 预设值、allowed 预设列表、font resolve 映射。后续若调整默认预设或预设集合，两处需同步更新。

## 7. 验证矩阵

| 场景 | 期望结果 |
|---|---|
| 清除 cookie 的新用户首屏 | 立即 anthropic（暖奶油 + 衬线），无黑白→anthropic 跳变 |
| cookie `theme_preset=default` | 黑白 default |
| cookie `theme_preset=anthropic` | anthropic |
| cookie `theme_preset=rose-garden` | rose-garden |
| 任意预设下刷新页面 | 首屏无 FOUC，主题保持 |
| 主题面板点"重置" | 回到 anthropic（DEFAULT 已改为 anthropic） |
| 手动选 default 后再刷新 | 保持 default（cookie 持久化） |

## 8. 风险与回滚

- **风险**：低。不搬动任何 CSS 变量值；provider 改动为单点；CSS 仅扩展选择器。
- **回滚**：`git revert` 本次提交即可恢复 `default` 为默认预设。
- **注意**：`data-theme-preset` 改动后对所有用户始终存在（包括默认用户）。已确认：JS/TS 代码中 `data-theme-preset` 仅在 `theme-customization-provider.tsx:139`（本次改动处）被引用，无其他代码依赖"`data-theme-preset` 属性缺失 == 默认预设"这一旧假设；CSS 中均为 `[data-theme-preset='xxx']` 正向匹配具体值。改动安全。
