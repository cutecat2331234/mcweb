import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

const page = readFileSync(
  resolve(process.cwd(), 'app/javascript/pages/Identity/Security/Show.vue'),
  'utf8',
)

test('security page distinguishes the active email from a pending replacement', () => {
  assert.match(page, /pending_email_change\?:/)
  assert.match(page, /v-if="pending_email_change"/)
  assert.match(page, /identity\.security\.pendingEmailTitle/)
  assert.match(page, /pending_email_change\.email/)
  assert.match(page, /pending_email_change\.expires_at/)
})

test('email change continues to use the shared form and UI components', () => {
  assert.match(page, /emailForm\.patch\(routes\.securityEmail/)
  assert.match(page, /<Alert/)
  assert.match(page, /<Input/)
  assert.match(page, /<Button/)
  assert.doesNotMatch(page, /<style\b/)
})
