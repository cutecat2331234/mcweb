import assert from 'node:assert/strict'
import { afterEach, test } from 'node:test'
import { confirm, confirmState, resolveConfirm } from '../../app/javascript/lib/useConfirm.ts'
import { prompt, promptState, resolvePrompt } from '../../app/javascript/lib/usePrompt.ts'

afterEach(() => {
  resolveConfirm(false)
  resolvePrompt(null)
})

test('an overlapping confirmation cancels only the new action before a dialog mounts', async () => {
  const first = confirm({ title: 'First action', message: 'Confirm the first action' })
  const owner = confirmState.resolve
  const duplicate = confirm({ title: 'Second action', message: 'Must not replace the first action' })

  assert.notStrictEqual(duplicate, first, 'a second action must not inherit the first confirmation')
  assert.strictEqual(confirmState.resolve, owner)
  assert.equal(confirmState.options.title, 'First action')
  assert.equal(confirmState.open, true)
  assert.equal(await duplicate, false)

  resolveConfirm(true)
  assert.equal(await first, true)
  assert.equal(confirmState.open, false)
  assert.equal(confirmState.resolve, null)
})

test('an overlapping prompt preserves the first request and its draft before a dialog mounts', async () => {
  const first = prompt({ title: 'First prompt', defaultValue: 'Original value' })
  const owner = promptState.resolve
  promptState.value = 'Edited value'
  const duplicate = prompt({ title: 'Second prompt', defaultValue: 'Wrong value' })

  assert.notStrictEqual(duplicate, first, 'a second action must not inherit the first answer')
  assert.strictEqual(promptState.resolve, owner)
  assert.equal(promptState.options.title, 'First prompt')
  assert.equal(promptState.value, 'Edited value')
  assert.equal(promptState.open, true)
  assert.equal(await duplicate, null)

  resolvePrompt(promptState.value)
  assert.equal(await first, 'Edited value')
  assert.equal(promptState.open, false)
  assert.equal(promptState.resolve, null)
})

test('confirmation load failure cancels its request and allows a fresh request', async () => {
  const first = confirm({ title: 'First action', message: 'Unavailable dialog' })
  const owner = confirmState.resolve

  resolveConfirm(false, owner)
  assert.equal(await first, false)
  assert.equal(confirmState.open, false)
  assert.equal(confirmState.resolve, null)

  const next = confirm({ title: 'Next action', message: 'Fresh request' })
  const nextOwner = confirmState.resolve
  resolveConfirm(false, owner)
  assert.strictEqual(confirmState.resolve, nextOwner, 'a stale failure must not cancel the new action')
  assert.equal(confirmState.open, true)
  resolveConfirm(true)
  assert.equal(await next, true)
})

test('prompt load failure cancels its request without cancelling or overwriting a later prompt', async () => {
  const first = prompt({ title: 'First prompt', defaultValue: 'Unavailable dialog' })
  const owner = promptState.resolve

  resolvePrompt(null, owner)
  assert.equal(await first, null)
  assert.equal(promptState.open, false)
  assert.equal(promptState.resolve, null)

  const next = prompt({ title: 'Next prompt', defaultValue: 'Fresh draft' })
  const nextOwner = promptState.resolve
  resolvePrompt(null, owner)
  assert.strictEqual(promptState.resolve, nextOwner, 'a stale failure must not cancel the new prompt')
  assert.equal(promptState.value, 'Fresh draft')
  assert.equal(promptState.open, true)
  resolvePrompt('New answer')
  assert.equal(await next, 'New answer')
})
