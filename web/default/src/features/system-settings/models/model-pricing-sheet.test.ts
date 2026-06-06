import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { describe, test } from 'node:test'

describe('model pricing editor panel actions', () => {
  test('does not render a local submit button in the editor footer', () => {
    const source = readFileSync(
      join(
        process.cwd(),
        'src/features/system-settings/models/model-pricing-sheet.tsx'
      ),
      'utf8'
    )

    const footerStart = source.indexOf('<SheetFooter')
    const footerEnd = source.indexOf('</SheetFooter>', footerStart)
    const footerSource = source.slice(footerStart, footerEnd)

    assert.equal(footerSource.includes("type='submit'"), false)
    assert.equal(footerSource.includes("t('Update')"), false)
    assert.equal(footerSource.includes("t('Add')"), false)
  })
})
