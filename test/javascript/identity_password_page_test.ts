import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

const page = readFileSync(
  resolve(process.cwd(), 'app/javascript/pages/Identity/Passwords/Edit.vue'),
  'utf8',
)

test('signed-in password change is a dedicated Arco form with complete verification fields', () => {
  assert.match(page, /from '@mcweb\/ui'/)
  assert.match(page, /<Form/)
  assert.match(page, /<InputPassword/)
  assert.match(page, /current_password/)
  assert.match(page, /new_password/)
  assert.match(page, /new_password_confirmation/)
  assert.match(page, /v-if="totp_enabled"/)
  assert.match(page, /autocomplete="one-time-code"/)
  assert.match(page, /inputmode="text"/)
  assert.doesNotMatch(page, /inputmode="numeric"/)
  assert.match(page, /routes\.securityPassword/)
  assert.doesNotMatch(page, /components\/ui\//)
  assert.doesNotMatch(page, /gradient|translate[XY]?\(/i)
})
