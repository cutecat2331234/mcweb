import { createI18n, type I18n } from 'vue-i18n'
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

export function createAppI18n(locale: AppLocale = 'zh-CN'): I18n {
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

export function syncI18nLocale(i18n: I18n, locale: unknown) {
  const next = normalizeAppLocale(locale)
  if (i18n.global.locale.value !== next) {
    i18n.global.locale.value = next
  }
}
