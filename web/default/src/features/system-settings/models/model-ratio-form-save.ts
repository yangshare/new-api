export async function saveModelRatioFormWithDraftCommit<
  Values extends Record<string, unknown>,
>({
  editMode,
  commitDraft,
  getValues,
  submitValues,
  submitForm,
}: {
  editMode: 'visual' | 'json'
  commitDraft: () => Promise<Partial<Values> | boolean>
  getValues?: () => Values
  submitValues?: (values: Values) => Promise<void> | void
  submitForm: () => Promise<void> | void
}) {
  if (editMode === 'visual') {
    const committed = await commitDraft()
    if (!committed) return

    if (committed !== true && getValues && submitValues) {
      await submitValues({
        ...getValues(),
        ...committed,
      } as Values)
      return
    }
  }

  await submitForm()
}
