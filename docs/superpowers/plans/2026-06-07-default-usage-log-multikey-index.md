# Default Usage Logs Multi-Key Index 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 在 default 前端普通使用日志的渠道列和详情弹窗中展示多 key 渠道本次请求选中的 key index。

**架构：** 后端和数据类型已经提供 `other.admin_info.is_multi_key` 与 `multi_key_index`。实现时先在 usage logs 格式工具中加入一个小型解析 helper，列表列和详情弹窗共享该 helper，确保旧日志、非多 key 日志、异常值都不展示额外标签。移动端复用表格 channel cell，无需单独改动。

**技术栈：** React 19、TypeScript、TanStack Table、shadcn-style local UI、Bun、node:test。

---

## 文件结构

- 修改：`web/src/features/usage-logs/lib/format.ts`
  - 职责：新增 `getMultiKeyIndex`，统一判断日志 `other` 是否应展示多 key index。
- 创建：`web/src/features/usage-logs/lib/format-multikey.test.ts`
  - 职责：覆盖 `getMultiKeyIndex` 的显示和隐藏条件。
- 修改：`web/src/features/usage-logs/components/columns/common-logs-columns.tsx`
  - 职责：在 admin common logs 的 Channel cell 中展示 `K{index}` 小标签。
- 修改：`web/src/features/usage-logs/components/dialogs/details-dialog.tsx`
  - 职责：在详情弹窗的 admin Channel 行中展示同样的 `K{index}` 小标签。

## 任务 1：添加 multi-key index 解析 helper

**文件：**
- 修改：`web/src/features/usage-logs/lib/format.ts`
- 创建：`web/src/features/usage-logs/lib/format-multikey.test.ts`

- [ ] **步骤 1：编写失败的测试**

创建 `web/src/features/usage-logs/lib/format-multikey.test.ts`，内容如下：

```ts
/*
Copyright (C) 2023-2026 QuantumNous

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program. If not, see <https://www.gnu.org/licenses/>.

For commercial licensing, please contact support@quantumnous.com
*/
import assert from 'node:assert/strict'
import { describe, test } from 'node:test'

import { getMultiKeyIndex } from './format'
import type { LogOtherData } from '../types'

describe('getMultiKeyIndex', () => {
  test('returns zero index for multi-key logs', () => {
    const other: LogOtherData = {
      admin_info: {
        is_multi_key: true,
        multi_key_index: 0,
      },
    }

    assert.equal(getMultiKeyIndex(other), 0)
  })

  test('returns positive index for multi-key logs', () => {
    const other: LogOtherData = {
      admin_info: {
        is_multi_key: true,
        multi_key_index: 3,
      },
    }

    assert.equal(getMultiKeyIndex(other), 3)
  })

  test('hides index when log is not marked as multi-key', () => {
    const other: LogOtherData = {
      admin_info: {
        is_multi_key: false,
        multi_key_index: 2,
      },
    }

    assert.equal(getMultiKeyIndex(other), null)
  })

  test('hides missing, non-numeric, and non-finite indexes', () => {
    assert.equal(getMultiKeyIndex(null), null)
    assert.equal(getMultiKeyIndex({}), null)
    assert.equal(
      getMultiKeyIndex({
        admin_info: {
          is_multi_key: true,
        },
      }),
      null
    )
    assert.equal(
      getMultiKeyIndex({
        admin_info: {
          is_multi_key: true,
          multi_key_index: Number.NaN,
        },
      }),
      null
    )
  })
})
```

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
cd web
bun test src/features/usage-logs/lib/format-multikey.test.ts
```

预期：FAIL。关键报错应说明 `getMultiKeyIndex` 没有从 `./format` 导出。

- [ ] **步骤 3：编写最少实现代码**

在 `web/src/features/usage-logs/lib/format.ts` 的 `parseLogOther` 函数后添加：

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
  if (typeof index !== 'number' || !Number.isFinite(index)) return null

  return index
}
```

- [ ] **步骤 4：运行测试验证通过**

运行：

```bash
cd web
bun test src/features/usage-logs/lib/format-multikey.test.ts
```

预期：PASS，4 个测试通过。

- [ ] **步骤 5：Commit**

```bash
git add web/src/features/usage-logs/lib/format.ts web/src/features/usage-logs/lib/format-multikey.test.ts
git commit -m "test(web): cover usage log multikey index parsing"
```

## 任务 2：在 common logs 渠道列显示 key index 标签

**文件：**
- 修改：`web/src/features/usage-logs/components/columns/common-logs-columns.tsx`
- 测试：`web/src/features/usage-logs/lib/format-multikey.test.ts`

- [ ] **步骤 1：运行现有 helper 测试建立基线**

运行：

```bash
cd web
bun test src/features/usage-logs/lib/format-multikey.test.ts
```

预期：PASS。这样确认本任务只改变 UI 接入，不破坏解析规则。

- [ ] **步骤 2：导入 helper**

在 `web/src/features/usage-logs/components/columns/common-logs-columns.tsx` 现有 `../../lib/format` 导入列表中加入 `getMultiKeyIndex`：

```ts
import {
  formatModelName,
  getFirstResponseTimeColor,
  getResponseTimeColor,
  getTieredBillingSummary,
  hasAnyCacheTokens,
  parseLogOther,
  isViolationFeeLog,
  getMultiKeyIndex,
} from '../../lib/format'
```

- [ ] **步骤 3：在 ChannelCell 中计算标签值**

在 `ChannelCell` 内 `const other = parseLogOther(log.other)` 之后加入：

```ts
const multiKeyIndex = getMultiKeyIndex(other)
const multiKeyLabel = multiKeyIndex === null ? null : `K${multiKeyIndex}`
const multiKeyTitle =
  multiKeyIndex === null
    ? undefined
    : `${t('Key')} ${t('Index')}: ${multiKeyIndex}`
```

- [ ] **步骤 4：调整渠道 badge 容器并渲染 key index**

将当前渠道 badge 容器从：

```tsx
<div className='relative inline-flex w-fit'>
  <StatusBadge
    label={channelIdDisplay}
    autoColor={String(log.channel)}
    copyText={String(log.channel)}
    size='sm'
    showDot={false}
    className='font-mono'
  />
  {affinity && (
```

改为：

```tsx
<div className='relative inline-flex w-fit items-center gap-1'>
  <StatusBadge
    label={channelIdDisplay}
    autoColor={String(log.channel)}
    copyText={String(log.channel)}
    size='sm'
    showDot={false}
    className='font-mono'
  />
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
  {affinity && (
```

Keep the existing affinity button block unchanged after this insertion.

- [ ] **步骤 5：运行类型检查**

运行：

```bash
cd web
bun run typecheck
```

预期：PASS。重点确认 JSX props、imports 和 `aria-label` 类型都合法。

- [ ] **步骤 6：Commit**

```bash
git add web/src/features/usage-logs/components/columns/common-logs-columns.tsx
git commit -m "feat(web): show multikey index in usage log channels"
```

## 任务 3：在详情弹窗 Channel 行显示 key index 标签

**文件：**
- 修改：`web/src/features/usage-logs/components/dialogs/details-dialog.tsx`
- 测试：`web/src/features/usage-logs/lib/format-multikey.test.ts`

- [ ] **步骤 1：导入 helper**

在 `web/src/features/usage-logs/components/dialogs/details-dialog.tsx` 的 `../../lib/format` 导入列表中加入 `getMultiKeyIndex`：

```ts
import {
  parseLogOther,
  getParamOverrideActionLabel,
  parseAuditLine,
  decodeBillingExprB64,
  getTieredBillingSummary,
  hasAnyCacheTokens,
  isViolationFeeLog,
  getFirstResponseTimeColor,
  getResponseTimeColor,
  getMultiKeyIndex,
} from '../../lib/format'
```

- [ ] **步骤 2：在 DetailsDialog 中计算标签值**

在 `const other = parseLogOther(props.log.other)` 之后加入：

```ts
const multiKeyIndex = getMultiKeyIndex(other)
const multiKeyLabel = multiKeyIndex === null ? null : `K${multiKeyIndex}`
const multiKeyTitle =
  multiKeyIndex === null
    ? undefined
    : `${t('Key')} ${t('Index')}: ${multiKeyIndex}`
```

- [ ] **步骤 3：更新 Channel 详情行渲染**

将 admin-only Channel detail row 的 `value` 从：

```tsx
value={
  <span>
    {props.log.channel}
    {props.log.channel_name && (
      <span className='text-muted-foreground'>
        {' '}
        ({props.log.channel_name})
      </span>
    )}
  </span>
}
```

改为：

```tsx
value={
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
}
```

- [ ] **步骤 4：运行 helper 测试和类型检查**

运行：

```bash
cd web
bun test src/features/usage-logs/lib/format-multikey.test.ts
bun run typecheck
```

预期：两个命令都 PASS。

- [ ] **步骤 5：Commit**

```bash
git add web/src/features/usage-logs/components/dialogs/details-dialog.tsx
git commit -m "feat(web): show multikey index in usage log details"
```

## 任务 4：最终验证

**文件：**
- 验证：`web/package.json`
- 验证：`web/src/features/usage-logs/components/usage-logs-mobile-card.tsx`

- [ ] **步骤 1：运行 usage logs helper 测试**

```bash
cd web
bun test src/features/usage-logs/lib/format-multikey.test.ts
```

预期：PASS。

- [ ] **步骤 2：运行 lint**

```bash
cd web
bun run lint
```

预期：PASS。

- [ ] **步骤 3：运行完整构建检查**

```bash
cd web
bun run build:check
```

预期：PASS。该命令会执行 `tsc -b && rsbuild build`。

- [ ] **步骤 4：人工检查移动端继承路径**

检查 `web/src/features/usage-logs/components/usage-logs-mobile-card.tsx`：

```tsx
<SummaryField
  label={t('Channel')}
  cell={cells.get('channel')}
  primaryOnly
/>
```

确认 common mobile card 仍然使用 `cells.get('channel')`，因此任务 2 的 ChannelCell 标签会进入移动端；不要添加移动端重复实现。

- [ ] **步骤 5：最终状态检查**

```bash
git status --short
```

预期：没有未提交改动。

如果有格式化、锁文件或无关改动，不要顺手提交；先确认它们是否由本计划产生。
