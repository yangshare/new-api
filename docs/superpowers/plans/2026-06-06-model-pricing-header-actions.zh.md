# 模型价格编辑面板 Header 操作区 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 将 `ModelPricingEditorPanel` 底部的操作按钮（取消、更新/添加）和草稿提示移动到面板 Header 区域，提升桌面端和移动端操作可达性。

**架构：** 调整 `ModelPricingEditorPanel` 内部 JSX 结构：将 Header `div` 从 form 外部移入 form 内部，在 Header 右侧添加取消/提交按钮，在 Header 下方保留草稿提示，然后删除原有的 `SheetFooter` 区域。不改动任何业务逻辑、数据流或组件接口。

**技术栈：** React 19, TypeScript, Tailwind CSS, shadcn/ui, Bun

---

## 文件结构

- **修改：** `web/src/features/system-settings/models/model-pricing-sheet.tsx`
  - 职责：将 `ModelPricingEditorPanel` 的 Footer 操作区上移合并到 Header，调整 JSX 层级使 Header 进入 `<form>` 内部，清理不再使用的 `SheetFooter` 和 `sideDrawerFooterClassName` 导入。

---

## 任务 1：修改 ModelPricingEditorPanel 布局

**文件：**
- 修改：`web/src/features/system-settings/models/model-pricing-sheet.tsx`

### 步骤 1：运行前端类型检查建立基线

- [ ] **运行基线类型检查**

```bash
cd web && bun run typecheck
```

**预期：** 命令成功退出（exit code 0），无类型错误输出。

---

### 步骤 2：将 Header 移入 form 并添加操作按钮

- [ ] **修改 `ModelPricingEditorPanel` 返回的 JSX 结构**

找到 `return (` 语句后外层 `<div>` 内的 Header 区域，将其从 `<Form>` 上方移入 `<form>` 内部，并在右侧添加取消和提交按钮。

**old_string（第740–767行区域）：**

```tsx
  return (
    <div
      className={cn(
        'bg-background flex min-h-0 flex-1 flex-col overflow-hidden rounded-xl border',
        className
      )}
    >
      <div className='border-b p-4'>
        <div className='flex flex-wrap items-start justify-between gap-3'>
          <div className='min-w-0'>
            <h3 className='truncate text-base font-medium'>
              {isEditMode ? t('Edit model pricing') : t('Add model pricing')}
            </h3>
            <p className='text-muted-foreground truncate text-sm'>
              {activeName}
            </p>
          </div>
          <Badge variant={getModeBadgeVariant(pricingMode)}>
            {t(getModeLabel(pricingMode))}
          </Badge>
        </div>
      </div>

      <Form {...form}>
        <form
          onSubmit={form.handleSubmit(handleSubmit)}
          className='flex min-h-0 flex-1 flex-col'
          autoComplete='off'
        >
```

**new_string：**

```tsx
  return (
    <div
      className={cn(
        'bg-background flex min-h-0 flex-1 flex-col overflow-hidden rounded-xl border',
        className
      )}
    >
      <Form {...form}>
        <form
          onSubmit={form.handleSubmit(handleSubmit)}
          className='flex min-h-0 flex-1 flex-col'
          autoComplete='off'
        >
          <div className='border-b p-4'>
            <div className='flex flex-wrap items-start justify-between gap-3'>
              <div className='min-w-0 flex-1'>
                <h3 className='truncate text-base font-medium'>
                  {isEditMode ? t('Edit model pricing') : t('Add model pricing')}
                </h3>
                <p className='text-muted-foreground truncate text-sm'>
                  {activeName}
                </p>
              </div>
              <div className='flex flex-wrap items-center gap-2'>
                <Badge variant={getModeBadgeVariant(pricingMode)}>
                  {t(getModeLabel(pricingMode))}
                </Badge>
                <Button
                  type='button'
                  variant='outline'
                  onClick={onCancel}
                  size='sm'
                >
                  {t('Cancel')}
                </Button>
                <Button type='submit' size='sm'>
                  {isEditMode ? t('Update') : t('Add')}
                </Button>
              </div>
            </div>
```

**变更说明：**
- 将 `Form` 和 `form` 标签上移，使其包裹 Header。
- 在 Header 右侧增加操作按钮组（取消 outline + 提交 primary）。
- 给左侧标题区添加 `flex-1`，确保标题在宽屏下占据可用空间。
- 按钮组外层使用 `flex flex-wrap`，允许按钮在窄屏时换行。
- 按钮使用 `size='sm'` 避免 Header 过高。

---

### 步骤 3：将草稿提示从 Footer 移到 Header 下方

- [ ] **在 Header `border-b` 容器内、标题按钮行下方追加草稿提示**

紧跟在上一步 `new_string` 末尾的 `</div>`（`flex-wrap` 那一行）之后，追加以下内容：

**old_string：**

```tsx
            </div>
          </div>

          <div className='min-h-0 flex-1 overflow-y-auto p-4'>
```

**new_string：**

```tsx
            </div>
            <div className='text-muted-foreground mt-2 text-xs'>
              {selectedTargetCount > 0
                ? t('{{count}} selected targets available for bulk copy.', {
                    count: selectedTargetCount,
                  })
                : t('Changes are written to the settings draft on save.')}
            </div>
          </div>

          <div className='min-h-0 flex-1 overflow-y-auto p-4'>
```

**变更说明：**
- 草稿提示从 Footer 移到 Header 下方，仍在 `border-b` 容器内。
- 保持原有文案和 `selectedTargetCount` 条件渲染逻辑不变。

---

### 步骤 4：删除 Footer 区域

- [ ] **删除原有的 `SheetFooter` 及内部操作按钮**

找到表单内容区结束后的 `SheetFooter` 块并删除。

**old_string：**

```tsx
          </div>

          <SheetFooter
            className={sideDrawerFooterClassName(
              'grid-cols-1 sm:items-center sm:justify-between'
            )}
          >
            <div className='text-muted-foreground text-xs'>
              {selectedTargetCount > 0
                ? t('{{count}} selected targets available for bulk copy.', {
                    count: selectedTargetCount,
                  })
                : t('Changes are written to the settings draft on save.')}
            </div>
            <div className='flex justify-end gap-2'>
              <Button type='button' variant='outline' onClick={onCancel}>
                {t('Cancel')}
              </Button>
              <Button type='submit'>
                {isEditMode ? t('Update') : t('Add')}
              </Button>
            </div>
          </SheetFooter>
        </form>
      </Form>
    </div>
  )
```

**new_string：**

```tsx
          </div>
        </form>
      </Form>
    </div>
  )
```

---

### 步骤 5：清理未使用的导入

- [ ] **移除 `SheetFooter` 和 `sideDrawerFooterClassName` 导入**

**old_string（第29–36行区域）：**

```tsx
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetFooter,
  SheetHeader,
  SheetTitle,
} from '@/components/ui/sheet'
```

**new_string：**

```tsx
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from '@/components/ui/sheet'
```

**old_string（第65–67行区域）：**

```tsx
import {
  sideDrawerContentClassName,
  sideDrawerFooterClassName,
} from '@/components/drawer-layout'
```

**new_string：**

```tsx
import { sideDrawerContentClassName } from '@/components/drawer-layout'
```

---

### 步骤 6：运行类型检查验证无新增错误

- [ ] **运行类型检查**

```bash
cd web && bun run typecheck
```

**预期：** 命令成功退出（exit code 0），无新增类型错误。如果出现与本次修改无关的既有错误，记录但不阻塞。

---

### 步骤 7：运行构建验证

- [ ] **运行生产构建**

```bash
cd web && bun run build
```

**预期：** 构建成功完成，无与 `model-pricing-sheet.tsx` 相关的编译错误。

---

### 步骤 8：Commit

- [ ] **提交变更**

```bash
git add web/src/features/system-settings/models/model-pricing-sheet.tsx
git commit -m "feat(ui): move model pricing editor actions to header

Move cancel and update/add buttons from footer to header in
ModelPricingEditorPanel for better accessibility on both desktop
and mobile. Keep the draft-save hint below the header. Remove
unused SheetFooter and sideDrawerFooterClassName imports."
```

---

## 自检

### 1. 规格覆盖度

| 规格需求 | 对应任务/步骤 |
|---|---|
| 将取消和更新/添加从 Footer 移到 Header | 任务 1 步骤 2、步骤 4 |
| 删除编辑器底部操作区 | 任务 1 步骤 4 |
| 保持现有提交和取消行为不变 | 按钮使用相同的 `onClick={onCancel}` 和 `type='submit'` |
| 删除 Footer 后保留草稿提示 | 任务 1 步骤 3 |
| 确保 Header 布局在桌面端和窄屏移动端都可用 | 使用 `flex-wrap` + `flex-1` + `min-w-0` + `truncate` |
| 不包含数据流、持久化、自动保存修改 | 无对应任务（确实未涉及） |
| 手动检查列表 | 见下方验证清单 |
| 自动化检查（类型检查/构建） | 任务 1 步骤 6、步骤 7 |

**无遗漏。**

### 2. 占位符扫描

- [x] 无 "TODO" / "待定" / "后续实现"
- [x] 无 "添加适当的错误处理" 等模糊描述
- [x] 无未定义的函数/类型引用
- [x] 每个代码步骤包含完整的 old_string/new_string

### 3. 类型一致性

- [x] `ModelPricingEditorPanelProps` 未变更，父组件无需修改
- [x] `selectedTargetCount`、`onCancel`、`handleSubmit` 在 Header 中的使用与 Footer 中一致
- [x] `isEditMode`、`pricingMode` 状态读取不变
- [x] `size='sm'` 是 `Button` 组件支持的合法 prop

---

## 执行交接

**计划已完成并保存到 `docs/superpowers/plans/2026-06-06-model-pricing-header-actions.zh.md`。两种执行方式：**

**1. 子代理驱动（推荐）** - 每个任务调度一个新的子代理，任务间进行审查，快速迭代

**2. 内联执行** - 在当前会话中使用 executing-plans 执行任务，批量执行并设有检查点

**选哪种方式？**

**如果选择子代理驱动：**
- **必需子技能：** 使用 superpowers:subagent-driven-development
- 每个任务一个新子代理 + 两阶段审查

**如果选择内联执行：**
- **必需子技能：** 使用 superpowers:executing-plans
- 批量执行并设有检查点供审查
