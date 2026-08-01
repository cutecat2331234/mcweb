import { createI18n } from 'vue-i18n'
import zhCN from '@/locales/zh-CN'
import en from '@/locales/en'
import {
  missingTranslation,
  normalizeAppLocale,
  type AppLocale,
} from './i18nRuntime'

export {
  MISSING_TRANSLATION_EVENT,
  normalizeAppLocale,
  type AppLocale,
  type MissingTranslationDetail,
} from './i18nRuntime'

export function createAppI18n(locale: AppLocale = 'zh-CN') {
  return createI18n({
    legacy: false,
    globalInjection: true,
    locale,
    fallbackLocale: 'en',
    missingWarn: false,
    fallbackWarn: false,
    missing: (missingLocale, key, _instance, type) => (
      missingTranslation(String(missingLocale), String(key), type)
    ),
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
  if (typeof document !== 'undefined') {
    document.documentElement.lang = next
  }
}

// Merge DB-backed admin "phrase overrides" (shared as a nested Inertia prop for
// the current locale) on top of the static locale messages, so overrides win.
export function applyPhraseOverrides(i18n: AppI18n, locale: unknown, overrides: unknown) {
  if (!overrides || typeof overrides !== 'object') return
  const target = normalizeAppLocale(locale)
  i18n.global.mergeLocaleMessage(target, overrides as Record<string, unknown>)
}
