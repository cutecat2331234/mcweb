/** Read Rails CSRF token from meta tag (preferred) or XSRF-TOKEN cookie fallback. */
export function readCsrfToken(): string {
  if (typeof document === 'undefined') return ''

  const meta = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content?.trim()
  if (meta) return meta

  const cookieMatch = document.cookie.match(/(?:^|;\s*)XSRF-TOKEN=([^;]*)/)
  if (cookieMatch?.[1]) return decodeURIComponent(cookieMatch[1])

  return ''
}

/** Keep meta tag in sync with the latest server-issued token. */
export function syncCsrfMetaTag(token?: string | null): void {
  const resolved = token?.trim() || readCsrfTokenFromCookie() || readCsrfToken()
  if (!resolved) return

  const meta = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')
  if (meta) meta.content = resolved
}

function readCsrfTokenFromCookie(): string {
  const cookieMatch = document.cookie.match(/(?:^|;\s*)XSRF-TOKEN=([^;]*)/)
  return cookieMatch?.[1] ? decodeURIComponent(cookieMatch[1]) : ''
}

export function csrfHeaders(): Record<string, string> {
  const token = readCsrfToken()
  if (!token) return {}

  return {
    'X-CSRF-Token': token,
    'X-XSRF-TOKEN': token,
  }
}
