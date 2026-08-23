import { router } from '@inertiajs/vue3'

import { csrfHeaders } from '@/lib/csrf'
import {
  frontendApplicationRequestHeaders,
  resolveFrontendRoute,
} from '@/lib/frontendApplications'
import { localeRequestHeaders } from '@/lib/localePreference'
import {
  approveNextDocumentNavigation,
  cancelDocumentNavigationApproval,
  confirmUnsavedNavigation,
} from '@/lib/unsavedForms'

export const DOCUMENT_NAVIGATION_ATTRIBUTE = 'data-mcweb-document-navigation'
export const SAFE_FRONTEND_LOCATION_HEADER = 'X-McWeb-Safe-Location'

function destinationUrl(value: unknown): URL | null {
  try {
    const url = value instanceof URL
      ? value
      : typeof value === 'string'
        ? new URL(value, window.location.href)
        : null
    if (!url || (url.protocol !== 'http:' && url.protocol !== 'https:')) return null
    return url
  } catch {
    return null
  }
  return null
}

function navigateDocument(url: URL): void {
  approveNextDocumentNavigation(url.href)
  try {
    window.location.assign(url.href)
  } catch (error) {
    cancelDocumentNavigationApproval()
    throw error
  }
}

function registeredDocumentUrl(value: unknown): URL | null {
  const url = destinationUrl(value)
  if (!url || url.origin !== window.location.origin) return null
  const match = resolveFrontendRoute(url.pathname, 'GET')
  return match && (match.rule.kind === 'document' || match.rule.kind === 'inertia_page')
    ? url
    : null
}

export function navigateFrontendDocument(value: string | URL): void {
  const url = registeredDocumentUrl(value)
  if (!url) throw new Error(`Unregistered frontend document destination: ${String(value)}`)
  navigateDocument(url)
}

export function recoverFrontendSafeLocation(value: unknown): boolean {
  if (typeof value !== 'string' || !value.startsWith('/') || value.startsWith('//')
    || value.includes('\\') || /[\u0000-\u001f\u007f]/.test(value)) return false
  const url = registeredDocumentUrl(value)
  if (!url) return false
  if (!confirmUnsavedNavigation()) return false
  navigateDocument(url)
  return true
}

function requestPath(url: URL): string {
  return `${url.pathname}${url.search}${url.hash}`
}

function isPlainPrimaryClick(event: MouseEvent): boolean {
  return event.button === 0
    && !event.ctrlKey
    && !event.metaKey
    && !event.shiftKey
    && !event.altKey
}

function sameDocumentFragment(current: URL, destination: URL): boolean {
  return destination.pathname === current.pathname
    && destination.search === current.search
    && destination.hash.length > 0
}

function visitMethod(visit: { method?: unknown }): string {
  return typeof visit.method === 'string' ? visit.method.toUpperCase() : 'GET'
}

export function installApplicationNavigation(applicationId: string): VoidFunction {
  const removeBefore = router.on('before', (event) => {
    const visit = event.detail.visit as {
      url?: unknown
      method?: unknown
      headers?: Record<string, string>
      prefetch?: boolean
    }
    const url = destinationUrl(visit.url)
    const method = visitMethod(visit)
    const match = url?.origin === window.location.origin
      ? resolveFrontendRoute(url.pathname, method)
      : null
    const allowedPage = method === 'GET'
      && match?.application?.id === applicationId
      && match?.rule.kind === 'inertia_page'
    const allowedAction = method !== 'GET'
      && method !== 'HEAD'
      && match?.application?.id === applicationId
      && match?.rule.kind === 'application_action'

    if (allowedPage || allowedAction) {
      if (allowedPage && !visit.prefetch && !confirmUnsavedNavigation()) {
        event.preventDefault()
        return false
      }
      visit.headers = {
        ...visit.headers,
        ...csrfHeaders(),
        ...localeRequestHeaders(),
        ...frontendApplicationRequestHeaders(applicationId),
      }
      return
    }

    event.preventDefault()
    if (!visit.prefetch && method === 'GET' && url) {
      if (!confirmUnsavedNavigation()) return false
      navigateDocument(url)
    }
    return false
  })

  const onDocumentClick = (event: MouseEvent) => {
    if (event.defaultPrevented || !isPlainPrimaryClick(event)) return
    const target = event.target
    if (!(target instanceof Element) || target.closest('[contenteditable="true"]')) return
    const anchor = target.closest<HTMLAnchorElement>('a[href]')
    if (!anchor || anchor.hasAttribute('download')) return
    const anchorTarget = anchor.getAttribute('target')
    if (anchorTarget && anchorTarget.toLowerCase() !== '_self') return
    const forceDocument = anchor.hasAttribute(DOCUMENT_NAVIGATION_ATTRIBUTE)
      || anchor.hasAttribute('data-portal-hard-navigation')
      || anchor.hasAttribute('data-admin-hard-navigation')

    const url = destinationUrl(anchor.getAttribute('href'))
    if (!url || url.origin !== window.location.origin) return
    const current = new URL(window.location.href)
    if (sameDocumentFragment(current, url)) return

    const match = resolveFrontendRoute(url.pathname, 'GET')
    if (!forceDocument
      && match?.application?.id === applicationId
      && match.rule.kind === 'inertia_page') {
      return
    }

    // Own every same-origin non-page primary click here, before an Inertia
    // Link's bubble handler can translate it into a second router visit.
    event.preventDefault()
    event.stopPropagation()
    if (!confirmUnsavedNavigation()) {
      return
    }
    navigateDocument(url)
  }

  const onApplicationClick = (event: MouseEvent) => {
    if (event.defaultPrevented || !isPlainPrimaryClick(event)) return
    const target = event.target
    if (!(target instanceof Element) || target.closest('[contenteditable="true"]')) return
    const anchor = target.closest<HTMLAnchorElement>('a[href]')
    if (!anchor || anchor.hasAttribute('download')) return
    const anchorTarget = anchor.getAttribute('target')
    if (anchorTarget && anchorTarget.toLowerCase() !== '_self') return
    const url = destinationUrl(anchor.getAttribute('href'))
    if (!url || url.origin !== window.location.origin) return
    const match = resolveFrontendRoute(url.pathname, 'GET')
    if (match?.application?.id !== applicationId || match.rule.kind !== 'inertia_page') return

    event.preventDefault()
    router.visit(requestPath(url))
  }

  document.addEventListener('click', onDocumentClick, true)
  document.addEventListener('click', onApplicationClick)
  return () => {
    removeBefore()
    document.removeEventListener('click', onDocumentClick, true)
    document.removeEventListener('click', onApplicationClick)
  }
}
