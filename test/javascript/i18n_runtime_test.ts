import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'
import {
  canonicalAppLocale,
  mergeLocaleMessages,
  missingTranslation,
  MISSING_TRANSLATION_EVENT,
  normalizeAppLocale,
} from '../../app/javascript/lib/i18nRuntime.ts'
import {
  beginStoragePreferenceTransaction,
} from '../../app/javascript/lib/storagePreferenceTransaction.ts'
import englishMessages from '../../app/javascript/locales/en.ts'
import chineseMessages from '../../app/javascript/locales/zh-CN.ts'

function messageAt(messages: object, key: string): unknown {
  return key.split('.').reduce<unknown>((value, segment) => {
    if (!value || typeof value !== 'object') return undefined
    return (value as Record<string, unknown>)[segment]
  }, messages)
}

test('application locale normalization stays explicit', () => {
  assert.equal(normalizeAppLocale('zh_Hans'), 'zh-CN')
  assert.equal(normalizeAppLocale('EN-gb'), 'en')
  assert.equal(normalizeAppLocale('unsupported'), 'zh-CN')
  assert.equal(canonicalAppLocale('zh'), 'zh-CN')
  assert.equal(canonicalAppLocale('unsupported'), null)
})

test('application locale domains extend shared roots without erasing base copy', () => {
  const merged = mergeLocaleMessages([
    {
      admin: {
        overview: 'Overview',
        dashboard: { title: 'Dashboard' },
      },
    },
    {
      admin: {
        chatManagement: { nav: 'Channel management' },
      },
      enterprise: { nav: { channels: 'Channels' } },
    },
  ])

  assert.equal(messageAt(merged, 'admin.overview'), 'Overview')
  assert.equal(messageAt(merged, 'admin.dashboard.title'), 'Dashboard')
  assert.equal(messageAt(merged, 'admin.chatManagement.nav'), 'Channel management')
  assert.equal(messageAt(merged, 'enterprise.nav.channels'), 'Channels')
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
  assert.match(source, /type AppLocaleMessageCatalog = Record<AppLocale, AppMessageSchema>/)
  assert.match(source, /ComposerOptions<AppI18nSchema, AppLocale>/)
  assert.match(source, /export type AppI18n = I18n<AppLocaleMessageCatalog, \{\}, \{\}, AppLocale, false>/)
  assert.match(source, /createI18n<false, AppI18nOptions>\(options\)/)
  assert.match(source, /setLocaleMessage\(next, vueI18nMessageSchema\(messages\)\)/)
  assert.doesNotMatch(source, /Partial<Record<AppLocale, AppMessages>>/)
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

test('locale preference transactions roll storage back unless the visit succeeds', () => {
  const storageKey = 'mcweb-locale'
  const values = new Map<string, string>([[storageKey, 'en']])
  const previousWindow = Object.getOwnPropertyDescriptor(globalThis, 'window')
  Object.defineProperty(globalThis, 'window', {
    configurable: true,
    value: {
      localStorage: {
        getItem: (key: string) => values.get(key) ?? null,
        setItem: (key: string, value: string) => values.set(key, value),
        removeItem: (key: string) => values.delete(key),
      },
    },
  })

  try {
    const failed = beginStoragePreferenceTransaction(storageKey, 'zh-CN')
    assert.equal(values.get(storageKey), 'zh-CN')
    failed.rollback()
    assert.equal(values.get(storageKey), 'en')

    values.delete(storageKey)
    const cancelled = beginStoragePreferenceTransaction(storageKey, 'zh-CN')
    cancelled.rollback()
    assert.equal(values.has(storageKey), false)

    const successful = beginStoragePreferenceTransaction(storageKey, 'zh-CN')
    successful.commit()
    successful.rollback()
    assert.equal(values.get(storageKey), 'zh-CN')
  } finally {
    if (previousWindow) {
      Object.defineProperty(globalThis, 'window', previousWindow)
    } else {
      delete (globalThis as { window?: unknown }).window
    }
  }
})

test('language switchers commit shared locale state only after the cross-application action succeeds', () => {
  for (const relativePath of [
    'app/javascript/components/portal/LanguageSwitcher.vue',
    'app/javascript/components/admin/AdminLanguageSwitcher.vue',
  ]) {
    const source = readFileSync(resolve(process.cwd(), relativePath), 'utf8')
    const preload = source.indexOf('await preloadAppLocale(locale)')
    const publishSelection = source.indexOf('beginAppLocalePreferenceTransaction(locale)')
    const startAction = source.indexOf('await performSharedAction(')
    const commit = source.indexOf('transaction.commit()')
    const documentVisit = source.indexOf('navigateFrontendDocument(window.location.href)')

    assert.ok(preload >= 0, `${relativePath} must preload the selected locale`)
    assert.ok(publishSelection >= 0, `${relativePath} must publish the selected locale`)
    assert.ok(preload < publishSelection, `${relativePath} must preload before publishing the preference`)
    assert.ok(startAction > publishSelection, `${relativePath} must publish the locale before the action`)
    assert.ok(commit > startAction, `${relativePath} must commit only after the action succeeds`)
    assert.ok(documentVisit > commit, `${relativePath} must navigate only after committing the preference`)
    assert.match(source, /documentFrontendApplicationId\(\)/)
    assert.match(source, /method: 'PATCH'/)
    assert.match(source, /data: \{ locale \}/)
    assert.match(source, /catch \(error\) \{\s*transaction\.rollback\(\)/)
  }
})

test('community preference copy belongs to the forum domain in both locale bundles', () => {
  const source = readFileSync(
    resolve(process.cwd(), 'app/javascript/pages/Community/Preferences/Show.vue'),
    'utf8',
  )
  const keys = [...source.matchAll(/t\('([^']+)'/g)]
    .map((match) => match[1])
    .filter((key) => key.startsWith('forum.preferences.'))

  assert.ok(keys.length > 20)
  assert.doesNotMatch(source, /t\('preferences\./)
  assert.doesNotMatch(source, /<button\b/)
  for (const key of new Set(keys)) {
    assert.equal(typeof messageAt(englishMessages, key), 'string', `missing English ${key}`)
    assert.equal(typeof messageAt(chineseMessages, key), 'string', `missing Chinese ${key}`)
  }
  assert.equal(messageAt(englishMessages, 'preferences.title'), undefined)
  assert.equal(messageAt(chineseMessages, 'preferences.title'), undefined)
})

test('explicit Inertia visit headers override shared locale and csrf defaults', () => {
  for (const relativePath of [
    'app/javascript/lib/createInertiaApplication.ts',
  ]) {
    const source = readFileSync(resolve(process.cwd(), relativePath), 'utf8')
    assert.match(
      source,
      /event\.detail\.visit\.headers\s*=\s*\{[\s\S]*?\.\.\.event\.detail\.visit\.headers,[\s\S]*?\.\.\.frontendApplicationRequestHeaders/,
    )
  }
})

test('Inertia resolves the target page locale before loading its component', () => {
  for (const relativePath of [
    'app/javascript/lib/createInertiaApplication.ts',
  ]) {
    const source = readFileSync(resolve(process.cwd(), relativePath), 'utf8')
    assert.match(source, /resolve: async \(name, targetPage\?: InertiaPageLike\)/)
    assert.match(source, /await syncLocaleFromPage\(targetPage\)[\s\S]*?return normalizeFrontendPageComponent\(await loader\(\)\)/)
    assert.match(source, /typeof locale !== 'string' \|\| locale\.trim\(\)\.length === 0/)
    assert.match(source, /const onSuccess = \(event: Event\) => \{[\s\S]*?void syncLocaleFromPage\(detail\.page\)/)
    assert.match(source, /document\.addEventListener\('inertia:success', onSuccess\)/)
  }
})

test('website block translations keep the nested selector shape in both locales', () => {
  for (const [locale, messages] of [
    ['en', englishMessages],
    ['zh-CN', chineseMessages],
  ] as const) {
    assert.equal(typeof messageAt(messages, 'admin.website.blocks.types.hero'), 'string', locale)
    assert.equal(typeof messageAt(messages, 'admin.website.blocks.types.richText'), 'string', locale)
    assert.equal(messageAt(messages, 'admin.website.blocks.hero'), undefined, locale)
    assert.equal(messageAt(messages, 'admin.website.blocks.richText'), undefined, locale)
  }
})

test('staff workspace return action names the application center in both locales', () => {
  assert.equal(messageAt(englishMessages, 'staffWorkspace.returnToApp'), 'Return to app center')
  assert.equal(messageAt(chineseMessages, 'staffWorkspace.returnToApp'), '返回应用中心')
})

test('only the active locale and requested application domains load during bootstrap', () => {
  const source = readFileSync(
    resolve(process.cwd(), 'app/javascript/lib/i18n.ts'),
    'utf8',
  )

  assert.match(source, /const localeDomainLoaders: Record<AppLocale, Record<string, LocaleDomainLoader>>/)
  assert.match(source, /core: \(\) => import\(['"]@\/locales\/domains\/zh-CN\/core['"]\)/)
  assert.match(source, /core: \(\) => import\(['"]@\/locales\/domains\/en\/core['"]\)/)
  assert.match(source, /const domains = localeDomains\(domainNames\)/)
  assert.match(source, /await loadLocaleMessages\(initialLocale, domains\)/)
  assert.match(source, /\[initialLocale\]: vueI18nMessageSchema\(messages\)/)
  assert.doesNotMatch(source, /import\s+zhCN\s+from/)
  assert.doesNotMatch(source, /import\s+en\s+from/)
  assert.match(source, /fallbackLocale:\s*\{[\s\S]*?'zh-CN': \[\][\s\S]*?en: \[\]/)
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
      reports[0]?.[0],
      `[McWeb I18N] Missing translation: locale=zh-CN type=translate key=${missingKey}`,
    )
    assert.equal(
      reports[1]?.[0],
      `[McWeb I18N] Missing translation: locale=en type=translate key=${missingKey}`,
    )
    assert.equal(MISSING_TRANSLATION_EVENT, 'mcweb:i18n-missing')
  } finally {
    console.error = originalError
  }
})
