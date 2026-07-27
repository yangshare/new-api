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

  test('hides negative and fractional indexes', () => {
    assert.equal(
      getMultiKeyIndex({
        admin_info: {
          is_multi_key: true,
          multi_key_index: -1,
        },
      }),
      null
    )
    assert.equal(
      getMultiKeyIndex({
        admin_info: {
          is_multi_key: true,
          multi_key_index: 1.5,
        },
      }),
      null
    )
  })
})
