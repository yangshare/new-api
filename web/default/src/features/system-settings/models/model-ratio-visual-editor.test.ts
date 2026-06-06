import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { describe, test } from 'node:test'

describe('model ratio visual editor notifications', () => {
  test('does not show a draft-saved toast when the editor draft is committed', () => {
    const source = readFileSync(
      join(
        process.cwd(),
        'src/features/system-settings/models/model-ratio-visual-editor.tsx'
      ),
      'utf8'
    )

    const staleToastText =
      'Pricing changes saved' +
      ' to draft. Click ' +
      '"Save model prices" to apply.'

    assert.equal(
      source.includes(staleToastText),
      false
    )
  })

  test('syncs editor drafts into the outer pricing form while editing', () => {
    const source = readFileSync(
      join(
        process.cwd(),
        'src/features/system-settings/models/model-ratio-visual-editor.tsx'
      ),
      'utf8'
    )

    assert.equal(source.includes('onDraftChange={persistPricingData}'), true)
  })
})
