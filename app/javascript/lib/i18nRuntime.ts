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

export function canonicalAppLocale(value: unknown): AppLocale | null {
  const raw = String(value || '').trim().toLowerCase().replaceAll('_', '-')
  if (raw === 'zh' || raw === 'zh-cn' || raw === 'zh-hans') return 'zh-CN'
  if (raw === 'en' || raw === 'en-us' || raw === 'en-gb') return 'en'
  return SUPPORTED_LOCALES.find((locale) => locale.toLowerCase() === raw) ?? null
}

export function normalizeAppLocale(value: unknown): AppLocale {
  return canonicalAppLocale(value) ?? 'zh-CN'
}

function isLocaleMessageRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value)
}

export function mergeLocaleMessages(
  domains: readonly Record<string, unknown>[],
): Record<string, unknown> {
  const merged: Record<string, unknown> = {}

  for (const domain of domains) {
    for (const [key, value] of Object.entries(domain)) {
      const current = merged[key]
      merged[key] = isLocaleMessageRecord(current) && isLocaleMessageRecord(value)
        ? mergeLocaleMessages([current, value])
        : value
    }
  }

  return merged
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
  const canonicalLocale = normalizeAppLocale(locale)
  captureMissingTranslation(canonicalLocale, key, type)
  return canonicalLocale === 'en'
    ? MISSING_TRANSLATION_PLACEHOLDER
    : undefined
}
