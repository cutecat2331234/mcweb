import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

const panel = readFileSync(
  resolve(process.cwd(), 'app/javascript/components/commerce/orders/PaymentDisputePanel.vue'),
  'utf8',
)
const uploader = readFileSync(
  resolve(process.cwd(), 'app/javascript/components/secure-evidence/SecureEvidenceUpload.vue'),
  'utf8',
)
const orderShow = readFileSync(
  resolve(process.cwd(), 'app/javascript/pages/Commerce/Orders/Show.vue'),
  'utf8',
)

test('customer dispute panel closes create timeline evidence and withdrawal journeys', () => {
  assert.match(panel, /from '@mcweb\/ui'/)
  assert.match(panel, /paymentDisputes\.create\.allowed/)
  assert.match(panel, /createForm\.post\(props\.paymentDisputes\.create\.url/)
  assert.match(panel, /v-for="entry in item\.timeline"/)
  assert.match(panel, /SharedSecureEvidenceUpload/)
  assert.match(panel, /item\.can_withdraw && item\.withdraw_url/)
  assert.match(panel, /arcoConfirm/)
  assert.match(orderShow, /PaymentDisputePanel/)
  assert.match(orderShow, /:payment-disputes="paymentDisputes"/)
})

test('mutations retain server URLs and stable request ids until success', () => {
  assert.match(panel, /request_id: createIdempotencyKey\(\)/)
  assert.match(
    panel,
    /onSuccess:[\s\S]*?next\.create\.allowed[\s\S]*?createForm\.dispute\.request_id = createIdempotencyKey\(\)/,
  )
  assert.match(panel, /withdrawalRequestIds\.get\(item\.public_id\)/)
  assert.match(panel, /router\.delete\(item\.withdraw_url/)
  assert.doesNotMatch(panel, /\/app\/store/)
  assert.doesNotMatch(panel, /window\.location/)
})

test('shared evidence uploader owns transport and scanning without domain copy', () => {
  assert.match(uploader, /from '@mcweb\/ui'/)
  assert.match(uploader, /body\.append\('subject_key', props\.subjectKey\)/)
  assert.match(uploader, /retryKeys\.get\(retryKey\) \|\| createIdempotencyKey\(\)/)
  assert.match(uploader, /body\.append\('idempotency_key', idempotencyKey\)/)
  assert.match(uploader, /waitForScan/)
  assert.match(uploader, /state === 'upload_failed'/)
  assert.match(panel, /activeEvidenceCount/)
  assert.match(panel, /\['uploading', 'pending', 'available', 'quarantined'\]/)
  assert.doesNotMatch(uploader, /forum\.reportAppeals/)
  assert.doesNotMatch(uploader, /commerce\.payment/)
})

test('customer UI never names staff-only dispute fields', () => {
  for (const forbidden of [
    'provider_dispute_id',
    'provider_payment_id',
    'assigned_to',
    'risk_level',
    'event.metadata',
    'event.actor',
    'internal_note',
  ]) {
    assert.doesNotMatch(panel, new RegExp(forbidden.replace('.', '\\.')))
  }
})
