import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
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

test('locale synchronization keeps the document language aligned after SPA visits', () => {
  const source = readFileSync(
    resolve(process.cwd(), 'app/javascript/lib/i18n.ts'),
    'utf8',
  )

  assert.match(source, /const next = normalizeAppLocale\(locale\)/)
  assert.match(source, /document\.documentElement\.lang = next/)
  assert.match(source, /writeSharedAppLocale\(next\)/)
  assert.match(source, /localeSyncGenerations/)
})

test('locale preference supplies a stable shared key and partitions Inertia caches', () => {
  const source = readFileSync(
    resolve(process.cwd(), 'app/javascript/lib/localePreference.ts'),
    'utf8',
  )

  assert.match(source, /SHARED_LOCALE_STORAGE_KEY = 'mcweb-locale'/)
  assert.match(source, /INERTIA_LOCALE_HEADER = 'X-McWeb-Locale'/)
  assert.match(source, /window\.localStorage\.setItem\(SHARED_LOCALE_STORAGE_KEY, normalized\)/)
  assert.match(source, /\[INERTIA_LOCALE_HEADER\]: normalizeAppLocale\(candidate\)/)
})

test('Inertia resolves the target page locale before loading its component', () => {
  for (const relativePath of [
    'app/javascript/entrypoints/inertia.ts',
    'app/javascript/entrypoints/admin.ts',
  ]) {
    const source = readFileSync(resolve(process.cwd(), relativePath), 'utf8')
    assert.match(source, /resolve: async \(name, targetPage\?: InertiaPageLike\)/)
    assert.match(source, /await syncLocaleFromInertiaPage\(targetPage\)[\s\S]*?return loader\(\)/)
    assert.match(source, /typeof locale !== 'string' \|\| locale\.trim\(\)\.length === 0/)
    assert.doesNotMatch(source, /inertia:success[\s\S]{0,500}void syncLocaleFromInertiaPage/)
  }
})

test('only the active locale is loaded during application bootstrap', () => {
  const source = readFileSync(
    resolve(process.cwd(), 'app/javascript/lib/i18n.ts'),
    'utf8',
  )

  assert.match(source, /'zh-CN': \(\) => import\(['"]@\/locales\/zh-CN['"]\)/)
  assert.match(source, /en: \(\) => import\(['"]@\/locales\/en['"]\)/)
  assert.doesNotMatch(source, /import\s+zhCN\s+from/)
  assert.doesNotMatch(source, /import\s+en\s+from/)
  assert.match(source, /fallbackLocale:\s*false/)
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
    assert.equal(
      reports[1]?.[0],
      `[McWeb I18N] Missing translation: locale=en type=translate key=${missingKey}`,
    )
    assert.equal(MISSING_TRANSLATION_EVENT, 'mcweb:i18n-missing')
  } finally {
    console.error = originalError
  }
})
