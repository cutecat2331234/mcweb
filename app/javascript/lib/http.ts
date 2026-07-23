import { csrfHeaders } from '@/lib/csrf'

/** Error thrown by getJson/postJson when the response status is not ok. */
export class HttpError extends Error {
  status: number
  body: unknown

  constructor(status: number, message: string, body: unknown) {
    super(message)
    this.name = 'HttpError'
    this.status = status
    this.body = body
  }
}

async function parseJson<T>(res: Response, method: string, url: string): Promise<T> {
  if (!res.ok) {
    const body = await res.json().catch(() => null)
    throw new HttpError(res.status, `${method} ${url} failed with ${res.status}`, body)
  }
  return res.json() as Promise<T>
}

/**
 * GET a URL expecting JSON. Merges CSRF headers, `Accept: application/json` and
 * same-origin credentials, checks `res.ok`, and returns the parsed body.
 * Throws {@link HttpError} (carrying the parsed error body) on non-2xx responses.
 */
export async function getJson<T = unknown>(url: string): Promise<T> {
  const res = await fetch(url, {
    method: 'GET',
    headers: {
      Accept: 'application/json',
      ...csrfHeaders(),
    },
    credentials: 'same-origin',
  })
  return parseJson<T>(res, 'GET', url)
}

export interface PostJsonOptions {
  method?: 'POST' | 'PATCH' | 'PUT' | 'DELETE'
}

/**
 * Send a JSON body to a URL (POST by default). Merges CSRF headers,
 * `Content-Type`/`Accept: application/json` and same-origin credentials,
 * checks `res.ok`, and returns the parsed body.
 * Throws {@link HttpError} (carrying the parsed error body) on non-2xx responses.
 */
export async function postJson<T = unknown>(
  url: string,
  body?: unknown,
  options: PostJsonOptions = {},
): Promise<T> {
  const { method = 'POST' } = options
  const res = await fetch(url, {
    method,
    headers: {
      'Content-Type': 'application/json',
      Accept: 'application/json',
      ...csrfHeaders(),
    },
    credentials: 'same-origin',
    body: body === undefined ? undefined : JSON.stringify(body),
  })
  return parseJson<T>(res, method, url)
}
