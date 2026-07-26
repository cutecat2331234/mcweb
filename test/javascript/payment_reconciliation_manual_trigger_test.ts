import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

function projectSource(relativePath: string) {
  return readFileSync(new URL(`../../${relativePath}`, import.meta.url), 'utf8')
}

test('payment reconciliation manual trigger uses bounded Arco controls and exact confirmation', () => {
  const source = projectSource(
    'app/javascript/pages/Admin/Store/PaymentReconciliations/Index.vue',
  )

  assert.match(source, /DatePicker,/)
  assert.match(source, /<Card v-if="manualTrigger\.allowed"/)
  assert.match(source, /v-if="manualTrigger\.ready"/)
  assert.match(source, /v-if="!manualTrigger\.ready"/)
  assert.match(source, /<DatePicker[\s\S]*?value-format="YYYY-MM-DD"/)
  assert.match(source, /<DatePicker[\s\S]*?format="YYYY-MM-DD"/)
  assert.match(source, /:disabled-date="disabledManualDate"/)
  assert.match(source, /value >= props\.manualTrigger\.minDate/)
  assert.match(source, /value <= props\.manualTrigger\.maxDate/)
  assert.match(source, /props\.manualTrigger\.confirmation/)
  assert.match(source, /postJson<[\s\S]*?>\(url, \{ date \}\)/)
  assert.match(source, /manualAuthorizedDate\.value !== manualForm\.date/)
  assert.match(source, /manualToken\.value = authorization\.token/)
  assert.match(source, /manualAuthorizationConfirmation\.value = authorization\.confirmation/)
  assert.match(
    source,
    /manualForm\.confirmation === expectedManualConfirmation\.value/,
  )
  assert.match(source, /manualSubmitting\.value = true[\s\S]*?router\.post\(/)
  assert.match(
    source,
    /router\.post\([\s\S]*?date: manualForm\.date,[\s\S]*?confirmation: manualForm\.confirmation,[\s\S]*?token,/,
  )
  assert.match(source, /:loading="manualSubmitting \|\| manualAuthorizationLoading"/)
  assert.match(source, /:disabled="!canSubmitManual"/)
  assert.match(source, /flex flex-col-reverse gap-2[\s\S]*?sm:flex-row/)
  assert.doesNotMatch(source, /<(?:input|select|button)(?:\s|>)/)
})

test('manual reconciliation copy stays symmetric in English and Chinese', () => {
  const english = projectSource('app/javascript/locales/en.ts')
  const chinese = projectSource('app/javascript/locales/zh-CN.ts')
  const keys = [
    'manualTitle',
    'manualHint',
    'manualUnavailable',
    'manualOpen',
    'manualDialogTitle',
    'manualWarning',
    'manualDate',
    'manualDatePlaceholder',
    'manualRange',
    'manualConfirmation',
    'manualConfirmationPlaceholder',
    'manualConfirmationHelp',
    'manualSubmit',
  ]

  for (const source of [english, chinese]) {
    assert.match(source, /paymentReconciliation:\s*\{/)
    for (const key of keys) {
      assert.match(source, new RegExp(`\\n\\s+${key}:`))
    }
  }
})

test('payment amounts respect each currency minor-unit exponent', () => {
  const source = projectSource(
    'app/javascript/pages/Admin/Store/PaymentReconciliations/Index.vue',
  )

  assert.match(source, /resolvedOptions\(\)\.maximumFractionDigits/)
  assert.match(source, /amount \/ \(10 \*\* fractionDigits\)/)
  assert.doesNotMatch(source, /amount \/ 100/)
})
