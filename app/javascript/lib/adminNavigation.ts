export const ADMIN_HARD_NAVIGATION_ATTRIBUTE = 'data-admin-hard-navigation'
const ADMIN_HARD_NAVIGATION_PATHS = new Set(['/admin/system/jobs'])

export interface AdminSpaHrefOptions {
  href: string
  currentHref: string
  target?: string | null
  download?: boolean
  hardNavigation?: boolean
}

type AdminVisit = (href: string) => void

export function isPlainPrimaryClick(
  event: Pick<MouseEvent, 'button' | 'ctrlKey' | 'metaKey' | 'shiftKey' | 'altKey'>,
) {
  return (
    event.button === 0
    && !event.ctrlKey
    && !event.metaKey
    && !event.shiftKey
    && !event.altKey
  )
}

export function resolveAdminSpaHref({
  href,
  currentHref,
  target,
  download = false,
  hardNavigation = false,
}: AdminSpaHrefOptions): string | null {
  if (download || hardNavigation || (target && target.toLowerCase() !== '_self')) return null

  let currentUrl: URL
  let destinationUrl: URL

  try {
    currentUrl = new URL(currentHref)
    destinationUrl = new URL(href, currentUrl)
  } catch {
    return null
  }

  if (destinationUrl.origin !== currentUrl.origin) return null
  if (ADMIN_HARD_NAVIGATION_PATHS.has(destinationUrl.pathname.replace(/\/+$/, ''))) return null
  if (destinationUrl.pathname !== '/admin' && !destinationUrl.pathname.startsWith('/admin/')) {
    return null
  }

  const isSameDocumentAnchor = (
    destinationUrl.pathname === currentUrl.pathname
    && destinationUrl.search === currentUrl.search
    && destinationUrl.hash.length > 0
  )
  if (isSameDocumentAnchor) return null

  return `${destinationUrl.pathname}${destinationUrl.search}${destinationUrl.hash}`
}

export function isAdminSpaNavigationHref(href: string, currentHref = window.location.href) {
  return resolveAdminSpaHref({ href, currentHref }) !== null
}

export function handleAdminSpaNavigationClick(
  event: MouseEvent,
  visit: AdminVisit,
  currentHref = window.location.href,
) {
  if (event.defaultPrevented || !isPlainPrimaryClick(event)) return false

  const target = event.target
  if (!(target instanceof Element)) return false
  if (target.closest('[contenteditable="true"]')) return false

  const anchor = target.closest<HTMLAnchorElement>('a[href]')
  if (!anchor) return false

  const href = resolveAdminSpaHref({
    href: anchor.getAttribute('href') || '',
    currentHref,
    target: anchor.getAttribute('target'),
    download: anchor.hasAttribute('download'),
    hardNavigation: anchor.hasAttribute(ADMIN_HARD_NAVIGATION_ATTRIBUTE),
  })
  if (!href) return false

  event.preventDefault()
  visit(href)
  return true
}

export function installAdminSpaNavigation(visit: AdminVisit) {
  const listener = (event: MouseEvent) => {
    handleAdminSpaNavigationClick(event, visit)
  }

  document.addEventListener('click', listener)
  return () => document.removeEventListener('click', listener)
}
