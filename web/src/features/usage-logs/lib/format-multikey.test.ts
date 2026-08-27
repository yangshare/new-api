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
import { describe, expect, test } from 'vitest'

import type { LogOtherData } from '../types'
import { getMultiKeyIndex } from './format'

describe('getMultiKeyIndex', () => {
  test('returns zero index for multi-key logs', () => {
    const other: LogOtherData = {
      admin_info: {
        is_multi_key: true,
        multi_key_index: 0,
      },
    }

    expect(getMultiKeyIndex(other)).toBe(0)
  })

  test('returns positive index for multi-key logs', () => {
    const other: LogOtherData = {
      admin_info: {
        is_multi_key: true,
        multi_key_index: 3,
      },
    }

    expect(getMultiKeyIndex(other)).toBe(3)
  })

  test('hides index when log is not marked as multi-key', () => {
    const other: LogOtherData = {
      admin_info: {
        is_multi_key: false,
        multi_key_index: 2,
      },
    }

    expect(getMultiKeyIndex(other)).toBe(null)
  })

  test('hides missing, non-numeric, and non-finite indexes', () => {
    expect(getMultiKeyIndex(null)).toBe(null)
    expect(getMultiKeyIndex({})).toBe(null)
    expect(
      getMultiKeyIndex({
        admin_info: {
          is_multi_key: true,
        },
      })
    ).toBe(null)
    expect(
      getMultiKeyIndex({
        admin_info: {
          is_multi_key: true,
          multi_key_index: Number.NaN,
        },
      })
    ).toBe(null)
  })

  test('hides negative and fractional indexes', () => {
    expect(
      getMultiKeyIndex({
        admin_info: {
          is_multi_key: true,
          multi_key_index: -1,
        },
      })
    ).toBe(null)
    expect(
      getMultiKeyIndex({
        admin_info: {
          is_multi_key: true,
          multi_key_index: 1.5,
        },
      })
    ).toBe(null)
  })
})
