import assert from 'node:assert/strict'
import { describe, test } from 'node:test'
import { saveModelRatioFormWithDraftCommit } from './model-ratio-form-save'

describe('model ratio form save flow', () => {
  test('commits the open visual editor draft before saving model prices', async () => {
    const calls: string[] = []

    await saveModelRatioFormWithDraftCommit<Record<string, string>>({
      editMode: 'visual',
      commitDraft: async () => {
        calls.push('commitDraft')
        return true
      },
      submitForm: async () => {
        calls.push('submitForm')
      },
    })

    assert.deepEqual(calls, ['commitDraft', 'submitForm'])
  })

  test('does not save model prices when draft validation fails', async () => {
    const calls: string[] = []

    await saveModelRatioFormWithDraftCommit({
      editMode: 'visual',
      commitDraft: async () => {
        calls.push('commitDraft')
        return false
      },
      submitForm: async () => {
        calls.push('submitForm')
      },
    })

    assert.deepEqual(calls, ['commitDraft'])
  })

  test('saves with values returned by the committed visual editor draft', async () => {
    const savedValues: Array<Record<string, string>> = []

    await saveModelRatioFormWithDraftCommit({
      editMode: 'visual',
      commitDraft: async () => ({
        ModelPrice: '{\n  "black-forest-labs/flux-1.1-pro": 0.04\n}',
      }),
      getValues: () => ({
        ModelPrice: '{}',
      }),
      submitValues: async (values) => {
        savedValues.push(values)
      },
      submitForm: async () => {
        throw new Error('submitForm should not be used for committed drafts')
      },
    })

    assert.deepEqual(savedValues, [
      {
        ModelPrice: '{\n  "black-forest-labs/flux-1.1-pro": 0.04\n}',
      },
    ])
  })
})
