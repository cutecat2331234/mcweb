import {
  normalizeAppLocale,
  type AppLocale,
} from './i18nRuntime'

export const SHARED_LOCALE_STORAGE_KEY = 'mcweb-locale'
export const INERTIA_LOCALE_HEADER = 'X-McWeb-Locale'

export function readSharedAppLocale(): AppLocale | null {
  if (typeof window === 'undefined') return null

  try {
    const stored = window.localStorage.getItem(SHARED_LOCALE_STORAGE_KEY)
    return stored === 'zh-CN' || stored === 'en' ? stored : null
  } catch {
    return null
  }
}

export function writeSharedAppLocale(locale: unknown): AppLocale {
  const normalized = normalizeAppLocale(locale)
  if (typeof window === 'undefined') return normalized

  try {
    window.localStorage.setItem(SHARED_LOCALE_STORAGE_KEY, normalized)
  } catch {
    // Storage can be unavailable in hardened or private browser contexts.
  }
  return normalized
}

export function localeRequestHeaders(locale?: unknown): Record<string, string> {
  const candidate = locale ?? readSharedAppLocale() ?? (
    typeof document === 'undefined' ? undefined : document.documentElement.lang
  )

  return {
    [INERTIA_LOCALE_HEADER]: normalizeAppLocale(candidate),
  }
}
