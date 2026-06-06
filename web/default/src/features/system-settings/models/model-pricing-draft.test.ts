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
import { buildModelPricingDraft } from './model-pricing-draft'

describe('buildModelPricingDraft', () => {
  test('switches a fixed-price model to token pricing even when stale price remains in form data', () => {
    const draft = buildModelPricingDraft({
      current: {
        modelPrice: '{"gpt-test":0.02}',
        modelRatio: '{}',
        cacheRatio: '{}',
        createCacheRatio: '{}',
        completionRatio: '{}',
        imageRatio: '{}',
        audioRatio: '{}',
        audioCompletionRatio: '{}',
        billingMode: '{}',
        billingExpr: '{}',
      },
      data: {
        name: 'gpt-test',
        billingMode: 'per-token',
        price: '0.02',
        ratio: '1.5',
        completionRatio: '2',
      },
    })

    assert.deepEqual(JSON.parse(draft.modelPrice), {})
    assert.deepEqual(JSON.parse(draft.modelRatio), { 'gpt-test': 1.5 })
    assert.deepEqual(JSON.parse(draft.completionRatio), { 'gpt-test': 2 })
  })
})
