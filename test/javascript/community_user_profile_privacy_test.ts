import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

const source = readFileSync(
  resolve(process.cwd(), 'app/javascript/pages/Community/Users/Show.vue'),
  'utf8',
)

test('private profile counters disappear instead of rendering as false zeroes', () => {
  assert.match(source, /v-if="profile\.forum_points !== undefined"/)
  assert.match(source, /v-if="profile\.orders_count !== undefined"/)
  assert.doesNotMatch(source, /profile\.forum_points \?\? 0/)
  assert.doesNotMatch(source, /profile\.orders_count \?\? 0/)
})
