# Model Pricing Header Actions Design

## Context

The model pricing editor currently places the `Cancel` and `Update` / `Add`
actions in the footer of `ModelPricingEditorPanel`. On desktop, the editor is a
sticky side panel beside the pricing table. On mobile, the same editor is shown
inside a sheet.

Long pricing forms, especially expression pricing and expanded save preview
content, make the footer inconvenient because administrators must scroll to the
bottom before they can apply the edit to the settings draft.

## Goal

Move the model pricing editor actions to the panel header so they are visible
immediately after opening the editor.

This change must not alter the existing two-step save flow:

1. `Update` / `Add` writes the single-model edit into the frontend settings
   draft.
2. `Save model prices` persists the updated pricing JSON options through the
   backend.

## Scope

In scope:

- Move `Cancel` and `Update` / `Add` from the editor footer to the header.
- Remove the editor footer action area.
- Preserve the existing submit and cancel behavior.
- Keep the draft-save hint visible somewhere in the editor after removing the
  footer.
- Ensure the header layout works on desktop and narrow mobile sheet widths.

Out of scope:

- Changing how model pricing data is saved to draft.
- Changing the final `Save model prices` persistence flow.
- Adding autosave.
- Refactoring pricing data storage or billing logic.

## Chosen Layout

Use a header with content on the left and actions on the right.

Left side:

- Editor title: `Edit model pricing` or `Add model pricing`.
- Active model name, truncated when necessary.
- Existing pricing mode badge.

Right side:

- `Cancel` outline button.
- `Update` / `Add` primary button.

For narrow screens, the header should wrap: title and metadata remain on the
first line or first block, and the actions move below or wrap to a separate row
without overlapping long model names.

## Behavior

The moved buttons keep their current behavior:

- `Cancel` calls the existing `onCancel` callback.
- `Update` / `Add` submits the existing form and calls the existing
  `handleSubmit`.
- Form validation behavior remains unchanged.
- Submit labels still depend on edit mode:
  - existing model: `Update`
  - new model: `Add`

The explanatory draft hint currently shown in the footer must remain available
after the footer is removed. It should be placed near the top of the editor,
below the header or near the save preview, so users still understand that the
single-model action only updates the draft.

## Components

Primary component:

- `web/default/src/features/system-settings/models/model-pricing-sheet.tsx`
  - `ModelPricingEditorPanel`

Related callers should not require behavior changes:

- `ModelPricingSheet`
- `ModelRatioVisualEditor`

## Data Flow

No data-flow changes are expected.

Current flow remains:

1. User edits model pricing fields.
2. Header `Update` / `Add` submits the editor form.
3. `ModelPricingEditorPanel.handleSubmit` builds `ModelRatioData`.
4. Parent `ModelRatioVisualEditor.handleSave` writes the model values into the
   pricing JSON draft maps.
5. Page-level `Save model prices` sends changed option values to
   `PUT /api/option/`.

## Error Handling

Existing form validation and error display remain unchanged.

The only layout-related error case is narrow width overflow. The header must use
wrapping, truncation, and flexible spacing so long model names do not overlap the
action buttons.

## Testing

Manual checks:

- Desktop pricing settings page:
  - open an existing model;
  - confirm `Cancel` and `Update` are visible without scrolling;
  - update each pricing mode: per-token, per-request, expression;
  - confirm the table draft updates after `Update`.
- Add-model flow:
  - confirm the primary button label is `Add`;
  - confirm draft data is added after submit.
- Mobile/narrow viewport:
  - open the sheet;
  - confirm header actions wrap cleanly and do not overlap the model name;
  - confirm submit and cancel still work.
- Confirm final persistence still requires page-level `Save model prices`.

Automated checks:

- Run frontend typecheck/build or the project's relevant frontend validation
  command after implementation.

