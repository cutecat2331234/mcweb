export type AppLocale = 'zh-CN' | 'en'

const SUPPORTED_LOCALES: AppLocale[] = [ 'zh-CN', 'en' ]
const MISSING_TRANSLATION_PLACEHOLDER = '…'
const reportedMissingTranslations = new Set<string>()

export const MISSING_TRANSLATION_EVENT = 'mcweb:i18n-missing'

export interface MissingTranslationDetail {
  locale: string
  key: string
  type: string
}

export function normalizeAppLocale(value: unknown): AppLocale {
  const raw = String(value || '').trim().toLowerCase().replace('_', '-')
  if (raw === 'zh' || raw === 'zh-cn' || raw === 'zh-hans') return 'zh-CN'
  if (raw === 'en' || raw === 'en-us' || raw === 'en-gb') return 'en'
  const match = SUPPORTED_LOCALES.find((locale) => locale.toLowerCase() === raw)
  return match || 'zh-CN'
}

export function captureMissingTranslation(locale: string, key: string, type = 'translate') {
  const fingerprint = `${locale}:${type}:${key}`
  if (reportedMissingTranslations.has(fingerprint)) return
  reportedMissingTranslations.add(fingerprint)

  const detail: MissingTranslationDetail = { locale, key, type }
  console.error(`[McWeb I18N] Missing translation: locale=${locale} type=${type} key=${key}`)

  if (typeof window !== 'undefined' && typeof window.dispatchEvent === 'function') {
    window.dispatchEvent(new CustomEvent<MissingTranslationDetail>(
      MISSING_TRANSLATION_EVENT,
      { detail },
    ))
  }
}

export function missingTranslation(
  locale: string,
  key: string,
  type = 'translate',
): string | undefined {
  captureMissingTranslation(locale, key, type)
  return locale.toLowerCase().startsWith('en')
    ? MISSING_TRANSLATION_PLACEHOLDER
    : undefined
}
