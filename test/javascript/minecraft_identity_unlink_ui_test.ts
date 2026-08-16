import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const page = readFileSync(
  new URL('../../app/javascript/pages/Minecraft/Link/Show.vue', import.meta.url),
  'utf8',
)

test('Minecraft link page gates unlink behind a target-specific danger modal', () => {
  assert.match(page, /unlinkAccount = ref<Account \| null>/)
  assert.match(page, /unlinkConfirmation\.value === unlinkAccount\.value\?\.unlinkConfirmation/)
  assert.match(page, /status="danger"/)
  assert.match(page, /unlinkWarningTitle/)
  assert.match(page, /unlinkConsequenceAccess/)
  assert.match(page, /unlinkConsequencePrimary/)
  assert.match(page, /unlinkConsequenceRequests/)
  assert.match(page, /unlinkConsequenceRelink/)
})

test('Minecraft unlink submits stale and duplicate protections while locking the modal', () => {
  assert.match(page, /createIdempotencyKey\(\)/)
  assert.match(page, /lock_version: account\.lockVersion/)
  assert.match(page, /idempotency_key: unlinkIdempotencyKey\.value/)
  assert.match(page, /:ok-loading="unlinkProcessing"/)
  assert.match(page, /:mask-closable="!unlinkProcessing"/)
  assert.match(page, /:closable="!unlinkProcessing"/)
  assert.match(page, /:disabled="unlinkProcessing"/)
})

test('Minecraft unlink confirmation is accessible and mobile-safe', () => {
  assert.match(page, /aria-describedby="minecraft-unlink-confirmation-help"/)
  assert.match(page, /:aria-label="t\('minecraft\.link\.unlinkAccountLabel'/)
  assert.match(page, /@media \(max-width: 575px\)/)
  assert.match(page, /overflow-wrap: anywhere/)
})
