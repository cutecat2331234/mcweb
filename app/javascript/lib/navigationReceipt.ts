import { csrfHeaders } from '@/lib/csrf'
import { localeRequestHeaders } from '@/lib/localePreference'

interface NavigationEffectOptions {
  method?: 'post' | 'patch'
  receiptToken?: string | null
}

export async function commitNavigationEffect(
  url: string | null | undefined,
  {
    method = 'post',
    receiptToken = null,
  }: NavigationEffectOptions = {},
): Promise<boolean> {
  if (!url || typeof window === 'undefined' || typeof document === 'undefined') {
    return false
  }

  try {
    const response = await fetch(url, {
      method: method.toUpperCase(),
      credentials: 'same-origin',
      keepalive: true,
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json',
        'X-Requested-With': 'XMLHttpRequest',
        ...csrfHeaders(),
        ...localeRequestHeaders(),
      },
      body: JSON.stringify(receiptToken ? { receipt_token: receiptToken } : {}),
    })

    return response.ok
  } catch {
    // Visit receipts are best-effort telemetry/read-state acknowledgements.
    // A failed receipt must never interrupt or replace the page the user opened.
    return false
  }
}
