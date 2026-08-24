const SIDEKIQ_ADMIN_PATH = '/admin/system/sidekiq'
const SIDEKIQ_WEB_PATH = '/jobs'
const SAFE_QUERY_KEYS = new Set([
  'count',
  'days',
  'direction',
  'only',
  'page',
  'period',
  'poll',
  'substr',
])

const METRICS_PERIODS = new Set(['1h', '2h', '4h', '8h', '24h', '48h', '72h'])
const METRICS_DETAIL_PERIODS = new Set(['1h', '2h', '4h', '8h'])
const MAX_QUERY_VALUE_BYTES = 512
const MAX_PATH_LENGTH = 2_048
const MAX_PAGE = 10_000
const MAX_PAGE_SIZE = 100
const textEncoder = new TextEncoder()

function parseSameOriginUrl(href: string, origin: string) {
  try {
    const expectedOrigin = new URL(origin).origin
    const url = new URL(href, expectedOrigin)
    return url.origin === expectedOrigin ? url : null
  }
  catch {
    return null
  }
}

function isSidekiqPath(pathname: string, allowProfileData = false) {
  if (textEncoder.encode(pathname).byteLength > MAX_PATH_LENGTH) return false
  if (pathname === SIDEKIQ_WEB_PATH
    || pathname === `${SIDEKIQ_WEB_PATH}/`) return true
  if (!pathname.startsWith(`${SIDEKIQ_WEB_PATH}/`)) return false

  const segments = pathname.slice(SIDEKIQ_WEB_PATH.length + 1).split('/')
  if (segments.some(segment => !isValidPathSegment(segment))) return false

  switch (segments[0]) {
    case 'busy':
      return segments.length === 1
    case 'queues':
    case 'morgue':
    case 'retries':
    case 'scheduled':
    case 'metrics':
      return segments.length === 1 || segments.length === 2
    case 'profiles':
      return segments.length === 1
        || (allowProfileData && segments.length === 3 && segments[2] === 'data')
    case 'cron':
      return segments.length === 1
        || (segments.length === 3 && segments[1] === 'namespaces')
        || (segments.length === 5
          && segments[1] === 'namespaces'
          && segments[3] === 'jobs')
    default:
      return false
  }
}

function isValidPathSegment(segment: string) {
  if (segment.length === 0) return false

  try {
    const decoded = decodeURIComponent(segment)
    return textEncoder.encode(decoded).byteLength <= 512
      && decoded !== '.'
      && decoded !== '..'
      && !/[\\/\u0000-\u001F\u007F]/.test(decoded)
  }
  catch {
    return false
  }
}

function boundedInteger(value: string, minimum: number, maximum: number) {
  if (!/^\d+$/.test(value)) return null

  const parsed = Number(value)
  if (!Number.isSafeInteger(parsed) || parsed < minimum || parsed > maximum) {
    return null
  }
  return String(parsed)
}

function sidekiqPathSegments(pathname: string) {
  if (pathname === SIDEKIQ_WEB_PATH
    || pathname === `${SIDEKIQ_WEB_PATH}/`) return []
  return pathname.slice(SIDEKIQ_WEB_PATH.length + 1).split('/')
}

function queryKeyAllowedForPath(key: string, pathname: string) {
  const segments = sidekiqPathSegments(pathname)
  const root = segments[0] || ''

  switch (key) {
    case 'days':
      return segments.length === 0
    case 'period':
      return root === 'metrics'
    case 'only':
      return segments.length === 1 && root === 'busy'
    case 'direction':
      return root === 'queues' && segments.length === 2
    case 'substr':
      return ['metrics', 'retries', 'scheduled', 'morgue'].includes(root)
        && segments.length === 1
    case 'count':
    case 'page':
      return (segments.length === 1 && root === 'busy')
        || (root === 'queues' && segments.length === 2)
        || (['retries', 'scheduled', 'morgue'].includes(root)
          && segments.length === 1)
    case 'poll':
      return segments.length > 0 && root !== 'metrics'
    default:
      return false
  }
}

function normalizeQueryValue(key: string, value: string, pathname: string) {
  if (textEncoder.encode(value).byteLength > MAX_QUERY_VALUE_BYTES) return null

  switch (key) {
    case 'count':
      return boundedInteger(value, 1, MAX_PAGE_SIZE)
    case 'days':
      return boundedInteger(value, 1, 180)
    case 'page':
      return boundedInteger(value, 1, MAX_PAGE)
    case 'direction':
      return value === 'asc' || value === 'desc' ? value : null
    case 'only':
      return value === 'jobs' || value === 'processes' ? value : null
    case 'period':
      if (!METRICS_PERIODS.has(value)) return null
      if (sidekiqPathSegments(pathname).length === 2
        && !METRICS_DETAIL_PERIODS.has(value)) return '8h'
      return value
    case 'poll':
      return value === 'true' ? value : null
    case 'substr':
      return value
    default:
      return null
  }
}

function safeSearch(url: URL) {
  const filtered = new URLSearchParams()

  for (const [key, value] of url.searchParams) {
    if (!SAFE_QUERY_KEYS.has(key)) continue
    if (!queryKeyAllowedForPath(key, url.pathname)) continue

    const normalizedValue = normalizeQueryValue(key, value, url.pathname)
    if (normalizedValue === null) continue

    filtered.set(key, normalizedValue)
  }

  const query = filtered.toString()
  return query ? `?${query}` : ''
}

export function normalizeSidekiqFrameUrl(href: string, origin: string) {
  const url = parseSameOriginUrl(href, origin)
  if (!url || !isSidekiqPath(url.pathname)) return null

  const pathname = url.pathname === SIDEKIQ_WEB_PATH
    ? `${SIDEKIQ_WEB_PATH}/`
    : url.pathname
  return `${pathname}${safeSearch(url)}`
}

export function normalizeSidekiqStandaloneUrl(href: string, origin: string) {
  const url = parseSameOriginUrl(href, origin)
  if (!url || !isSidekiqPath(url.pathname, true)) return null

  const pathname = url.pathname === SIDEKIQ_WEB_PATH
    ? `${SIDEKIQ_WEB_PATH}/`
    : url.pathname
  return `${pathname}${safeSearch(url)}`
}

export function adminUrlFromSidekiqFrameUrl(href: string, origin: string) {
  const url = parseSameOriginUrl(href, origin)
  if (!url || !isSidekiqPath(url.pathname)) return null

  const suffix = url.pathname === SIDEKIQ_WEB_PATH
    || url.pathname === `${SIDEKIQ_WEB_PATH}/`
    ? ''
    : url.pathname.slice(SIDEKIQ_WEB_PATH.length)
  return `${SIDEKIQ_ADMIN_PATH}${suffix}${safeSearch(url)}`
}

export function isSidekiqAdminReturnUrl(href: string, origin: string) {
  const url = parseSameOriginUrl(href, origin)
  return url?.pathname === SIDEKIQ_ADMIN_PATH && url.search === ''
}
