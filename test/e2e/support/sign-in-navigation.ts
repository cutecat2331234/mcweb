import type { Page, Request, Response } from '@playwright/test'

function documentUrl(value: string, base?: string): URL | null {
  try {
    const url = new URL(value, base)
    if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password) return null
    url.hash = ''
    return url
  } catch {
    return null
  }
}

export function acceptanceSignInDocumentLocation(response: Response, identityKey: string): string | null {
  const status = response.status()
  if (status >= 200 && status < 400) return null

  const location = response.headers()['x-inertia-location']
  const source = documentUrl(response.url())
  const target = location && !/[\\\u0000-\u001f\u007f]/.test(location)
    ? documentUrl(location, response.url())
    : null
  if (status === 409 && response.request().headers()['x-inertia'] === 'true'
    && source && target && target.origin === source.origin) {
    return target.href
  }

  throw new Error(`${identityKey} acceptance sign-in returned HTTP ${status} without a valid document handoff`)
}

export function hasSuccessfulSignInDocumentHandoff(
  page: Page,
  target: string,
  responses: readonly Response[],
): boolean {
  const current = documentUrl(page.url())
  const destination = documentUrl(target)
  if (!current || !destination || current.origin !== destination.origin) return false
  return responses.some((response) => {
    const request = response.request()
    const status = response.status()
    if (!((status >= 200 && status < 300) || status === 304)
      || !request.isNavigationRequest() || request.frame() !== page.mainFrame()
      || documentUrl(response.url())?.href !== current.href) return false

    let reachedDestination = false
    for (let redirected: Request | null = request; redirected; redirected = redirected.redirectedFrom()) {
      const redirectedDocument = documentUrl(redirected.url())
      if (!redirectedDocument || redirectedDocument.origin !== destination.origin) return false
      if (redirectedDocument.href === destination.href) reachedDestination = true
    }
    return reachedDestination
  })
}

export async function submitAcceptanceSignIn(page: Page, identityKey: string): Promise<void> {
  const documents: Response[] = []
  const onResponse = (response: Response) => {
    if (response.request().isNavigationRequest()) documents.push(response)
  }
  // Observe before clicking: a fast document handoff may finish before the
  // original POST response promise resumes. A changed SPA URL is not evidence.
  page.on('response', onResponse)
  try {
    const [response] = await Promise.all([
      page.waitForResponse((candidate) => candidate.request().method() === 'POST'
        && new URL(candidate.url()).pathname === '/app/identity/session'),
      page.getByRole('button', { name: 'Sign in', exact: true }).click(),
    ])
    const target = acceptanceSignInDocumentLocation(response, identityKey)
    await page.waitForURL((url) => !url.pathname.endsWith('/identity/sign-in'), { waitUntil: 'load' })
    if (target && !hasSuccessfulSignInDocumentHandoff(page, target, documents)) {
      throw new Error(`${identityKey} acceptance sign-in did not complete its successful document handoff`)
    }
  } finally {
    page.off('response', onResponse)
  }
}
