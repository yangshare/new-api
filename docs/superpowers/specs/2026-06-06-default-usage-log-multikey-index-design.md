# Default Usage Logs Multi-Key Index Display Design

## Goal

Bring the default frontend usage log channel display to parity with the classic frontend by showing the selected multi-key index for admin-visible usage logs.

The displayed value is the key index stored in `other.admin_info.multi_key_index`, not a database key ID or secret key content.

## Current State

- Backend already records multi-key metadata in log `other.admin_info`:
  - `is_multi_key`
  - `multi_key_index`
- Default frontend type definitions already include both fields in `LogOtherData`.
- Classic frontend displays the multi-key index next to the channel tag.
- Default frontend currently displays channel ID, channel name, retry chain, and channel affinity, but not the multi-key index.

## Scope

In scope:

- Default frontend common usage logs channel column.
- Default frontend common usage log details dialog.
- Mobile common usage log cards through their existing reuse of the channel table cell.

Out of scope:

- Backend changes.
- Database schema changes.
- Classic frontend changes.
- Midjourney drawing logs and async task logs.
- Any display of actual API key content.

## Data Contract

Use the existing parsed `LogOtherData` shape:

```ts
other?.admin_info?.is_multi_key
other?.admin_info?.multi_key_index
```

Display the key index only when:

- `admin_info.is_multi_key === true`
- `admin_info.multi_key_index` is a finite number

If either condition is not met, render nothing extra. Old logs and non-multi-key logs must keep their current UI.

## UI Design

### Channel Column

File:

- `web/default/src/features/usage-logs/components/columns/common-logs-columns.tsx`

Within `ChannelCell`:

- Keep the existing channel ID badge as the primary visual element.
- Add a small adjacent badge when a valid multi-key index exists.
- Use compact text `K{index}`, for example `K0`, `K1`, `K2`.
- Add a tooltip title or accessible label equivalent to `Key index: {index}`.
- Keep existing channel affinity marker behavior unchanged.
- Keep existing channel name sensitive visibility behavior unchanged.

The index badge should be visible when the channel ID is visible. The key index is routing metadata, not secret material.

### Details Dialog

File:

- `web/default/src/features/usage-logs/components/dialogs/details-dialog.tsx`

Within the admin-only Channel detail row:

- Keep the existing channel ID and optional channel name.
- Add the same `K{index}` small badge after the channel name when a valid multi-key index exists.
- Do not add a new separate detail row unless layout pressure requires it during implementation.

### Mobile Cards

File:

- `web/default/src/features/usage-logs/components/usage-logs-mobile-card.tsx`

No direct mobile-specific change is planned. The common mobile card uses the existing channel cell, so the channel column change should flow into mobile automatically.

## Error Handling and Compatibility

- If `other` is empty or invalid JSON, existing `parseLogOther` behavior applies and no key index badge is displayed.
- If `multi_key_index` is absent, null, non-numeric, or not finite, no badge is displayed.
- If `is_multi_key` is false or absent, no badge is displayed even if `multi_key_index` exists.
- Existing channel affinity, retry chain, copy, and sensitive visibility behavior must remain unchanged.

## Test and Verification Plan

Automated verification:

- Run frontend lint from `web/default`.
- Run TypeScript/build verification if available in the project scripts.

Manual verification:

- Admin common usage log with no multi-key metadata shows unchanged channel UI.
- Admin common usage log with `is_multi_key: true` and `multi_key_index: 0` shows `K0` in the channel column and details dialog.
- Admin common usage log with `multi_key_index: 1` shows `K1`.
- Old log with missing `admin_info` does not show a placeholder.
- Sensitive visibility off still hides channel name but keeps channel ID and key index visible.
- Mobile common usage log card shows the same channel key index through the reused channel cell.

## Implementation Notes

Prefer a tiny local helper in `common-logs-columns.tsx` if it improves readability, for example a function that returns `number | null` from `LogOtherData | null`. Keep the helper close to usage unless a second file needs it.

If details dialog needs the same validation logic, either duplicate the two-line guard locally or move the helper to `features/usage-logs/lib/format.ts`. For this narrow change, local guards are acceptable and avoid introducing a broader abstraction prematurely.
