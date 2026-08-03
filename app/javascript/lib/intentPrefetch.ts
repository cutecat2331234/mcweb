import { router } from '@inertiajs/vue3'
import { csrfHeaders } from '@/lib/csrf'

const DEFAULT_HOVER_DELAY = 150
const DEFAULT_CACHE_FOR = '30s'
const PREFETCHABLE_PREFIXES = [ '/app', '/admin' ]

interface NetworkInformationLike {
  saveData?: boolean
  effectiveType?: string
}

function connectionAllowsPrefetch(): boolean {
  if (typeof navigator === 'undefined') return false
  const connection = (navigator as Navigator & { connection?: NetworkInformationLike }).connection
  if (!connection) return true
  if (connection.saveData) return false
  return ![ 'slow-2g', '2g' ].includes(connection.effectiveType || '')
}

function intentElement(target: EventTarget | null): HTMLElement | null {
  if (!(target instanceof Element)) return null
  return target.closest<HTMLElement>('a[href], [data-prefetch-href]')
}

function prefetchHref(element: HTMLElement): string | null {
  if (element.closest('[data-no-prefetch]')) return null
  if (element instanceof HTMLAnchorElement) {
    if (element.target === '_blank' || element.hasAttribute('download')) return null
    const method = element.dataset.method || element.dataset.inertiaMethod
    if (method && method.toLowerCase() !== 'get') return null
  }

  const explicitHref = element.dataset.prefetchHref
  const raw = explicitHref ||
    (element instanceof HTMLAnchorElement ? element.getAttribute('href') : null)
  if (!raw || raw.startsWith('#')) return null

  const url = new URL(raw, window.location.href)
  if (url.origin !== window.location.origin) return null
  const current = new URL(window.location.href)
  const currentIsAdmin = current.pathname === '/admin' || current.pathname.startsWith('/admin/')
  const targetIsAdmin = url.pathname === '/admin' || url.pathname.startsWith('/admin/')
  if (currentIsAdmin !== targetIsAdmin) return null

  const knownAppPath = PREFETCHABLE_PREFIXES.some(
    (prefix) => url.pathname === prefix || url.pathname.startsWith(`${prefix}/`),
  )
  // Explicit destinations are used by Arco menu items and buttons that render
  // without an anchor. They may also point to a public website page such as
  // /blog or a configured /:slug page, but never cross the admin entry boundary.
  if (!explicitHref && !knownAppPath) {
    return null
  }

  if (url.pathname === current.pathname && url.search === current.search) return null
  return `${url.pathname}${url.search}${url.hash}`
}

export function installIntentPrefetch({
  hoverDelay = DEFAULT_HOVER_DELAY,
  cacheFor = DEFAULT_CACHE_FOR,
}: {
  hoverDelay?: number
  cacheFor?: string
} = {}): VoidFunction {
  if (typeof document === 'undefined' || !connectionAllowsPrefetch()) return () => {}

  let pendingElement: HTMLElement | null = null
  let pendingTimer: number | null = null

  const cancelPending = () => {
    if (pendingTimer !== null) window.clearTimeout(pendingTimer)
    pendingTimer = null
    pendingElement = null
  }

  const onPointerOver = (event: PointerEvent) => {
    if (event.pointerType && event.pointerType !== 'mouse') return
    if (document.visibilityState !== 'visible') return

    const element = intentElement(event.target)
    if (!element || element === pendingElement) return
    const href = prefetchHref(element)
    if (!href) return

    cancelPending()
    pendingElement = element
    pendingTimer = window.setTimeout(() => {
      pendingTimer = null
      pendingElement = null
      if (router.getCached(href) || router.getPrefetching(href)) return
      router.prefetch(
        href,
        { headers: csrfHeaders() },
        { cacheFor },
      )
    }, hoverDelay)
  }

  const onPointerOut = (event: PointerEvent) => {
    if (!pendingElement) return
    const related = event.relatedTarget
    if (related instanceof Node && pendingElement.contains(related)) return
    if (intentElement(event.target) === pendingElement) cancelPending()
  }

  document.addEventListener('pointerover', onPointerOver)
  document.addEventListener('pointerout', onPointerOut)

  return () => {
    cancelPending()
    document.removeEventListener('pointerover', onPointerOver)
    document.removeEventListener('pointerout', onPointerOut)
  }
}
