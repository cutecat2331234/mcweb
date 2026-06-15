/** Read Rails CSRF token from cookie (preferred) or meta tag fallback. */
export function readCsrfToken(): string {
  if (typeof document === 'undefined') return ''

  const cookieMatch = document.cookie.match(/(?:^|;\s*)XSRF-TOKEN=([^;]*)/)
  if (cookieMatch?.[1]) return decodeURIComponent(cookieMatch[1])

  return document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? ''
}

/** Keep meta tag in sync after Inertia visits refresh the XSRF-TOKEN cookie. */
export function syncCsrfMetaTag(): void {
  const token = readCsrfToken()
  if (!token) return

  const meta = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')
  if (meta) meta.content = token
}

export function csrfHeaders(): Record<string, string> {
  const token = readCsrfToken()
  if (!token) return {}

  return {
    'X-CSRF-Token': token,
    'X-XSRF-TOKEN': token,
  }
}
