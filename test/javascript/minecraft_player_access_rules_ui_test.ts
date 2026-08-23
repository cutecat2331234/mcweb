import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const source = readFileSync(
  new URL('../../app/javascript/pages/Admin/Minecraft/PlayerAccessRules/Index.vue', import.meta.url),
  'utf8',
)

test('Minecraft player access rules use the shared Arco interaction language', () => {
  assert.match(source, /<a-page-header/)
  assert.match(source, /<a-form/)
  assert.match(source, /<a-select/)
  assert.match(source, /<a-radio-group/)
  assert.match(source, /<a-date-picker/)
  assert.match(source, /<a-table/)
  assert.match(source, /<a-modal/)
  assert.doesNotMatch(source, /<(?:button|input|select|textarea|table)(?:\s|>)/)
  assert.doesNotMatch(source, /<style\b/)
  assert.doesNotMatch(source, /transition|transform|gradient/i)
})

test('the browser submits only bounded intent and never a raw connector command', () => {
  assert.match(source, /rule_type:/)
  assert.match(source, /username:/)
  assert.match(source, /reason:/)
  assert.match(source, /idempotency_key:/)
  assert.doesNotMatch(source, /console_command|exec_command|run_commands/)
})
