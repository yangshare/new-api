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
import { combineBillingExpr } from '../../pricing/lib/billing-expr'
import { safeJsonParse } from '../utils/json-parser'

export type PricingMode = 'per-token' | 'per-request' | 'tiered_expr'

export type ModelPricingDraftData = {
  name: string
  price?: string
  ratio?: string
  cacheRatio?: string
  createCacheRatio?: string
  completionRatio?: string
  imageRatio?: string
  audioRatio?: string
  audioCompletionRatio?: string
  billingMode?: PricingMode
  billingExpr?: string
  requestRuleExpr?: string
}

export type ModelPricingDraftCurrent = {
  modelPrice: string
  modelRatio: string
  cacheRatio: string
  createCacheRatio: string
  completionRatio: string
  imageRatio: string
  audioRatio: string
  audioCompletionRatio: string
  billingMode: string
  billingExpr: string
}

export type ModelPricingDraftValues = ModelPricingDraftCurrent

type BuildModelPricingDraftOptions = {
  current: ModelPricingDraftCurrent
  data: ModelPricingDraftData
  targetNames?: string[]
}

function setIfPresent(
  target: Record<string, number>,
  name: string,
  value: string | undefined
) {
  if (!value || value === '') return
  const parsed = parseFloat(value)
  if (Number.isFinite(parsed)) target[name] = parsed
}

function stringifyMap<T>(value: Record<string, T>) {
  return JSON.stringify(value, null, 2)
}

export function buildModelPricingDraft({
  current,
  data,
  targetNames = [data.name],
}: BuildModelPricingDraftOptions): ModelPricingDraftValues {
  const priceMap = safeJsonParse<Record<string, number>>(current.modelPrice, {
    fallback: {},
    silent: true,
  })
  const ratioMap = safeJsonParse<Record<string, number>>(current.modelRatio, {
    fallback: {},
    silent: true,
  })
  const cacheMap = safeJsonParse<Record<string, number>>(current.cacheRatio, {
    fallback: {},
    silent: true,
  })
  const createCacheMap = safeJsonParse<Record<string, number>>(
    current.createCacheRatio,
    { fallback: {}, silent: true }
  )
  const completionMap = safeJsonParse<Record<string, number>>(
    current.completionRatio,
    { fallback: {}, silent: true }
  )
  const imageMap = safeJsonParse<Record<string, number>>(current.imageRatio, {
    fallback: {},
    silent: true,
  })
  const audioMap = safeJsonParse<Record<string, number>>(current.audioRatio, {
    fallback: {},
    silent: true,
  })
  const audioCompletionMap = safeJsonParse<Record<string, number>>(
    current.audioCompletionRatio,
    { fallback: {}, silent: true }
  )
  const billingModeMap = safeJsonParse<Record<string, string>>(
    current.billingMode,
    { fallback: {}, silent: true }
  )
  const billingExprMap = safeJsonParse<Record<string, string>>(
    current.billingExpr,
    { fallback: {}, silent: true }
  )

  targetNames.forEach((name) => {
    delete priceMap[name]
    delete ratioMap[name]
    delete cacheMap[name]
    delete createCacheMap[name]
    delete completionMap[name]
    delete imageMap[name]
    delete audioMap[name]
    delete audioCompletionMap[name]
    delete billingModeMap[name]
    delete billingExprMap[name]

    if (data.billingMode === 'tiered_expr') {
      const combined = combineBillingExpr(
        data.billingExpr || '',
        data.requestRuleExpr || ''
      )
      if (combined) {
        billingModeMap[name] = 'tiered_expr'
        billingExprMap[name] = combined
      }
      setIfPresent(priceMap, name, data.price)
      setIfPresent(ratioMap, name, data.ratio)
      setIfPresent(cacheMap, name, data.cacheRatio)
      setIfPresent(createCacheMap, name, data.createCacheRatio)
      setIfPresent(completionMap, name, data.completionRatio)
      setIfPresent(imageMap, name, data.imageRatio)
      setIfPresent(audioMap, name, data.audioRatio)
      setIfPresent(audioCompletionMap, name, data.audioCompletionRatio)
    } else if (data.billingMode === 'per-request') {
      setIfPresent(priceMap, name, data.price)
    } else {
      setIfPresent(ratioMap, name, data.ratio)
      setIfPresent(cacheMap, name, data.cacheRatio)
      setIfPresent(createCacheMap, name, data.createCacheRatio)
      setIfPresent(completionMap, name, data.completionRatio)
      setIfPresent(imageMap, name, data.imageRatio)
      setIfPresent(audioMap, name, data.audioRatio)
      setIfPresent(audioCompletionMap, name, data.audioCompletionRatio)
    }
  })

  return {
    modelPrice: stringifyMap(priceMap),
    modelRatio: stringifyMap(ratioMap),
    cacheRatio: stringifyMap(cacheMap),
    createCacheRatio: stringifyMap(createCacheMap),
    completionRatio: stringifyMap(completionMap),
    imageRatio: stringifyMap(imageMap),
    audioRatio: stringifyMap(audioMap),
    audioCompletionRatio: stringifyMap(audioCompletionMap),
    billingMode: stringifyMap(billingModeMap),
    billingExpr: stringifyMap(billingExprMap),
  }
}
