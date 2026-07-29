import assert from 'node:assert/strict'
import test from 'node:test'
import {
  missingTranslation,
  MISSING_TRANSLATION_EVENT,
  normalizeAppLocale,
} from '../../app/javascript/lib/i18nRuntime.ts'

test('application locale normalization stays explicit', () => {
  assert.equal(normalizeAppLocale('zh_Hans'), 'zh-CN')
  assert.equal(normalizeAppLocale('EN-gb'), 'en')
  assert.equal(normalizeAppLocale('unsupported'), 'zh-CN')
})

test('runtime translation misses are reported once and never render the raw key', () => {
  const originalError = console.error
  const reports: unknown[][] = []
  console.error = (...args: unknown[]) => { reports.push(args) }

  try {
    const missingKey = 'runtime.contract.intentionally_missing'
    assert.equal(missingTranslation('zh', missingKey), undefined)
    const first = missingTranslation('en', missingKey)
    const second = missingTranslation('en', missingKey)

    assert.equal(first, '…')
    assert.equal(second, '…')
    assert.doesNotMatch(first, /runtime\.contract/)
    assert.equal(reports.length, 2)
    assert.equal(MISSING_TRANSLATION_EVENT, 'mcweb:i18n-missing')
  } finally {
    console.error = originalError
  }
})
