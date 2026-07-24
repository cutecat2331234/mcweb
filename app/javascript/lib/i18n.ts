import { createI18n } from 'vue-i18n'
import zhCN from '@/locales/zh-CN'
import en from '@/locales/en'

export type AppLocale = 'zh-CN' | 'en'

const SUPPORTED_LOCALES: AppLocale[] = [ 'zh-CN', 'en' ]

export function normalizeAppLocale(value: unknown): AppLocale {
  const raw = String(value || '').trim().toLowerCase().replace('_', '-')
  if (raw === 'zh' || raw === 'zh-cn' || raw === 'zh-hans') return 'zh-CN'
  if (raw === 'en' || raw === 'en-us' || raw === 'en-gb') return 'en'
  const match = SUPPORTED_LOCALES.find((locale) => locale.toLowerCase() === raw)
  return match || 'zh-CN'
}

export function createAppI18n(locale: AppLocale = 'zh-CN') {
  return createI18n({
    legacy: false,
    globalInjection: true,
    locale,
    fallbackLocale: 'en',
    messages: {
      'zh-CN': zhCN,
      en,
    },
  })
}

export type AppI18n = ReturnType<typeof createAppI18n>

export function syncI18nLocale(i18n: AppI18n, locale: unknown) {
  const next = normalizeAppLocale(locale)
  if (i18n.global.locale.value !== next) {
    i18n.global.locale.value = next
  }
}

// Merge DB-backed admin "phrase overrides" (shared as a nested Inertia prop for
// the current locale) on top of the static locale messages, so overrides win.
export function applyPhraseOverrides(i18n: AppI18n, locale: unknown, overrides: unknown) {
  if (!overrides || typeof overrides !== 'object') return
  const target = normalizeAppLocale(locale)
  i18n.global.mergeLocaleMessage(target, overrides as Record<string, unknown>)
}
