import {
  canonicalAppLocale,
  normalizeAppLocale,
  type AppLocale,
} from './i18nRuntime'
import {
  beginStoragePreferenceTransaction,
} from './storagePreferenceTransaction'
import {
  clearLocaleCookie,
  readLocaleCookie,
  writeLocaleCookie,
} from './localeBridge'

export const SHARED_LOCALE_STORAGE_KEY = 'mcweb-locale'
export const INERTIA_LOCALE_HEADER = 'X-McWeb-Locale'

export type AppLocalePreferenceTransaction = {
  locale: AppLocale
  commit: () => void
  rollback: () => void
}

export function readSharedAppLocale(): AppLocale | null {
  if (typeof window === 'undefined') return null

  try {
    const stored = window.localStorage.getItem(SHARED_LOCALE_STORAGE_KEY)
    const locale = canonicalAppLocale(stored)
    if (locale) {
      if (stored !== locale) window.localStorage.setItem(SHARED_LOCALE_STORAGE_KEY, locale)
      if (readLocaleCookie() !== locale) writeLocaleCookie(locale)
      return locale
    }
  } catch {
    // Fall through to the same-origin locale cookie shared with document renderers.
  }
  const cookieLocale = readLocaleCookie()
  if (!cookieLocale) return null
  try {
    window.localStorage.setItem(SHARED_LOCALE_STORAGE_KEY, cookieLocale)
  } catch {
    // The canonical cookie still keeps document navigations consistent.
  }
  return cookieLocale
}

export function writeSharedAppLocale(locale: unknown): AppLocale {
  const normalized = normalizeAppLocale(locale)
  if (typeof window === 'undefined') return normalized

  try {
    window.localStorage.setItem(SHARED_LOCALE_STORAGE_KEY, normalized)
  } catch {
    // Storage can be unavailable in hardened or private browser contexts.
  }
  writeLocaleCookie(normalized)
  return normalized
}

export function beginAppLocalePreferenceTransaction(
  locale: unknown,
): AppLocalePreferenceTransaction {
  const normalized = normalizeAppLocale(locale)
  const previousCookie = readLocaleCookie()
  const transaction = beginStoragePreferenceTransaction(
    SHARED_LOCALE_STORAGE_KEY,
    normalized,
  )

  return {
    locale: normalized,
    commit() {
      writeLocaleCookie(normalized)
      transaction.commit()
    },
    rollback() {
      transaction.rollback()
      if (previousCookie) writeLocaleCookie(previousCookie)
      else clearLocaleCookie()
    },
  }
}

export function localePreferenceVisitCallbacks(
  transaction: AppLocalePreferenceTransaction,
) {
  return {
    onSuccess: () => transaction.commit(),
    onError: () => transaction.rollback(),
    onCancel: () => transaction.rollback(),
    onHttpException: () => transaction.rollback(),
    onNetworkError: () => transaction.rollback(),
  }
}

export function localeRequestHeaders(locale?: unknown): Record<string, string> {
  const candidate = locale ?? readSharedAppLocale() ?? (
    typeof document === 'undefined' ? undefined : document.documentElement.lang
  )

  return {
    [INERTIA_LOCALE_HEADER]: normalizeAppLocale(candidate),
  }
}
