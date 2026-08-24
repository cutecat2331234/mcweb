import {
  canonicalAppLocale,
  type AppLocale,
} from '@/lib/i18nRuntime'

export const LOCALE_COOKIE_NAME = 'mcweb_locale'
const LOCALE_COOKIE_MAX_AGE = 60 * 60 * 24 * 365

export function validatedLocale(value: unknown): AppLocale | null {
  return canonicalAppLocale(value)
}

export function readLocaleCookie(): AppLocale | null {
  if (typeof document === 'undefined') return null
  const prefix = `${LOCALE_COOKIE_NAME}=`
  const value = document.cookie
    .split(';')
    .map((part) => part.trim())
    .find((part) => part.startsWith(prefix))
    ?.slice(prefix.length)
  if (!value) return null
  try {
    const decoded = decodeURIComponent(value)
    const locale = validatedLocale(decoded)
    if (locale && decoded !== locale) writeLocaleCookie(locale)
    return locale
  } catch {
    return null
  }
}

export function writeLocaleCookie(locale: AppLocale): void {
  if (typeof document === 'undefined') return
  const secure = window.location.protocol === 'https:' ? '; Secure' : ''
  document.cookie = `${LOCALE_COOKIE_NAME}=${encodeURIComponent(locale)}; Path=/; `
    + `Max-Age=${LOCALE_COOKIE_MAX_AGE}; SameSite=Lax${secure}`
}

export function clearLocaleCookie(): void {
  if (typeof document === 'undefined') return
  document.cookie = `${LOCALE_COOKIE_NAME}=; Path=/; Max-Age=0; SameSite=Lax`
}
