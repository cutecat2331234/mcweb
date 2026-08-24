import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

test('reaction users use an Arco popover with a native trigger root', () => {
  const source = readFileSync(
    resolve(process.cwd(), 'app/javascript/components/portal/ReactionUsersPopover.vue'),
    'utf8',
  )

  assert.match(source, /Popover,[\s\S]*from '@mcweb\/ui'/)
  assert.match(source, /<Popover[\s\S]*?<span class="inline-flex">[\s\S]*?<Button/)
  assert.match(source, /:popup-visible="open"/)
  assert.match(source, /@update:popup-visible="updateOpen"/)
  assert.doesNotMatch(source, /<button\b|<a-popover|:disabled=/)
})
