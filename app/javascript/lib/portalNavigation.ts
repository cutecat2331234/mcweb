export const PORTAL_HARD_NAVIGATION_ATTRIBUTE = 'data-portal-hard-navigation'

export interface PortalSpaHrefOptions {
  href: string
  currentHref: string
  target?: string | null
  download?: boolean
  hardNavigation?: boolean
}

type PortalVisit = (href: string) => void

function isPlainPrimaryClick(
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

export function resolvePortalSpaHref({
  href,
  currentHref,
  target,
  download = false,
  hardNavigation = false,
}: PortalSpaHrefOptions): string | null {
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
  if (destinationUrl.pathname !== '/app' && !destinationUrl.pathname.startsWith('/app/')) {
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

export function handlePortalSpaNavigationClick(
  event: MouseEvent,
  visit: PortalVisit,
  currentHref = window.location.href,
) {
  if (event.defaultPrevented || !isPlainPrimaryClick(event)) return false

  const target = event.target
  if (!(target instanceof Element)) return false
  if (target.closest('[contenteditable="true"]')) return false

  const anchor = target.closest<HTMLAnchorElement>('a[href]')
  if (!anchor) return false

  const href = resolvePortalSpaHref({
    href: anchor.getAttribute('href') || '',
    currentHref,
    target: anchor.getAttribute('target'),
    download: anchor.hasAttribute('download'),
    hardNavigation: anchor.hasAttribute(PORTAL_HARD_NAVIGATION_ATTRIBUTE),
  })
  if (!href) return false

  event.preventDefault()
  visit(href)
  return true
}

export function installPortalSpaNavigation(visit: PortalVisit) {
  const listener = (event: MouseEvent) => {
    handlePortalSpaNavigationClick(event, visit)
  }

  document.addEventListener('click', listener)
  return () => document.removeEventListener('click', listener)
}
