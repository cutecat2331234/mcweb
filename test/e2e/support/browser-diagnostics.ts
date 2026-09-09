import type { ConsoleMessage, Frame, Page, Request, Response, TestInfo } from '@playwright/test'

type DiagnosticKind = 'console.error' | 'framework.warning' | 'pageerror' | 'requestfailed' | 'http'
type DiagnosticContext = { application: string; step: string; pageUrl: string }
type RequestContext = DiagnosticContext & { document: number; frameInDocument: boolean }

export type BrowserDiagnostic = DiagnosticContext & {
  kind: DiagnosticKind
  message: string
  url?: string
  method?: string
  resourceType?: string
  status?: number
}

type Observation = {
  diagnostic: BrowserDiagnostic
  document: number
  navigationAbort?: boolean
  navigationAttempt?: number
  protocolTarget?: string
  protocolConsoleUrl?: string
}

export type BrowserDiagnosticReport = {
  errors: BrowserDiagnostic[]
  expected: Array<BrowserDiagnostic & { reason: string }>
  documents: Array<DiagnosticContext & { url: string; status: number }>
}

export type DiagnosticAttachment = Pick<TestInfo, 'attach'>

const capabilityPathPatterns = [
  /(\/app\/identity\/password_resets\/)(?!new(?:\/|$))[^/]+/,
  /(\/app\/identity\/security\/totp\/recovery\/)(?!new(?:\/|$))[^/]+/,
  /(\/app\/store\/compare\/)(?!(?:toggle|import_wishlist)(?:\/|$))[^/]+(?=\/?$)/,
  /(\/app\/store\/wishlist\/)(?!(?:share|add_all_to_cart|filter_presets)(?:\/|$))[^/]+(?=\/?$)/,
  /(\/app\/store\/downloads\/)[^/]+(?=\/?$)/,
  /(\/minecraft\/sync\/)[^/]+(?=\/?$)/,
]

function diagnosticPathname(pathname: string): string {
  return capabilityPathPatterns.reduce(
    (value, pattern) => value.replace(pattern, '$1[redacted]'),
    pathname,
  )
}

// Keep URLs useful without writing credentials, signed queries, or fragments
// into CI attachments. Never serialize console arguments, headers, or bodies.
export function diagnosticUrl(value: string): string {
  try {
    const url = new URL(value)
    return ['http:', 'https:'].includes(url.protocol)
      ? `${url.origin}${diagnosticPathname(url.pathname)}`
      : '(non-http document)'
  } catch {
    return '(unavailable)'
  }
}

export function diagnosticText(value: string): string {
  return value
    .replace(/https?:\/\/[^\s<>"'`]+/g, (url) => diagnosticUrl(url))
    .replace(
      /(["']?authorization["']?\s*[:=]\s*)["']?(?:Bearer|Basic)\s+[^\s"',;}]+["']?/gi,
      '$1[redacted]',
    )
    .replace(/(["']?(?:set-cookie|cookie)["']?\s*[:=]\s*)[^\r\n]*/gi, '$1[redacted]')
    .replace(
      /((?:["']?(?:password|authorization|cookie|[\w-]*(?:token|secret))["']?)\s*[:=]\s*)(?:"[^"\n]*"|'[^'\n]*'|[^\s,;}]+)/gi,
      '$1[redacted]',
    )
}

// Browser tips, generic deprecations, and application notices are not errors.
// These framework warnings do identify broken rendering/translation contracts.
const brokenFrameworkContract = /^(?:\[Vue warn\]:|\[intlify\] (?:Not found|Detected HTML)|\[McWeb\] .*Inertia network error)/
const cancelledRequest = /^(?:net::ERR_ABORTED|NS_BINDING_ABORTED)$/
const protocolConsoleMessage = /^Failed to load resource: the server responded with a status of 409(?: \([^\n]*\))?$/

function comparableUrl(value: string | undefined, base?: string): string | null {
  if (!value) return null
  try {
    const url = new URL(value, base)
    if (!['http:', 'https:'].includes(url.protocol)) return null
    url.hash = ''
    return url.href
  } catch {
    return null
  }
}

export function captureBrowserDiagnostics(
  page: Page,
  { application = 'unknown', step = 'page setup' }: { application?: string; step?: string } = {},
) {
  let applicationId = application
  let currentStep = step
  let documentVersion = 0
  let navigationSequence = 0
  let activeNavigationAttempt: number | undefined
  let stopped = false
  const requests = new WeakMap<Request, RequestContext>()
  const navigationAttempts = new WeakMap<Request, number>()
  const observations: Observation[] = []
  const documents: BrowserDiagnosticReport['documents'] = []
  const pendingDocuments = new Map<string, { attempt: number; destinations: string[] }>()
  const committedDocuments = new Map<string, number>()
  const committedNavigationAttempts = new Set<number>()
  const replacingNavigationAttempts = new Map<number, number>()

  function context(): DiagnosticContext {
    return {
      application: applicationId,
      step: diagnosticText(currentStep),
      pageUrl: diagnosticUrl(page.url()),
    }
  }

  function requestContext(request: Request): RequestContext {
    return requests.get(request) ?? { ...context(), document: documentVersion, frameInDocument: false }
  }

  function mainFrameRequest(request: Request): boolean {
    // Service-worker-originated requests do not necessarily have a frame.
    try {
      return request.frame() === page.mainFrame()
    } catch {
      return false
    }
  }

  function documentFrameRequest(request: Request): boolean {
    try {
      let frame = request.frame()
      while (frame.parentFrame()) frame = frame.parentFrame()!
      return frame === page.mainFrame()
    } catch {
      return false
    }
  }

  function requestSummary(request: Request) {
    const { document: _document, frameInDocument: _frameInDocument, ...origin } = requestContext(request)
    return {
      ...origin,
      url: diagnosticUrl(request.url()),
      method: request.method(),
      resourceType: request.resourceType(),
    }
  }

  const onRequest = (request: Request) => {
    requests.set(request, {
      ...context(),
      document: documentVersion,
      frameInDocument: documentFrameRequest(request),
    })
    if (request.isNavigationRequest() && mainFrameRequest(request)) {
      const redirectedFrom = request.redirectedFrom()
      const attempt = redirectedFrom ? navigationAttempts.get(redirectedFrom) : undefined
      const navigationAttempt = attempt ?? ++navigationSequence
      navigationAttempts.set(request, navigationAttempt)
      activeNavigationAttempt = navigationAttempt
    }
  }

  const onConsole = (message: ConsoleMessage) => {
    const level = message.type()
    const value = message.text()
    if (level !== 'error' && !(level === 'warning' && brokenFrameworkContract.test(value))) return
    observations.push({
      document: documentVersion,
      diagnostic: {
        ...context(),
        kind: level === 'error' ? 'console.error' : 'framework.warning',
        message: diagnosticText(value),
        url: diagnosticUrl(message.location().url),
      },
      protocolConsoleUrl: level === 'error' && protocolConsoleMessage.test(value)
        ? comparableUrl(message.location().url) ?? undefined
        : undefined,
    })
  }

  const onPageError = (error: Error) => {
    observations.push({
      document: documentVersion,
      diagnostic: { ...context(), kind: 'pageerror', message: diagnosticText(error.stack || error.message) },
    })
  }

  const onRequestFailed = (request: Request) => {
    const error = request.failure()?.errorText || 'Unknown request failure'
    const origin = requestContext(request)
    const navigationAttempt = origin.document < documentVersion
      ? replacingNavigationAttempts.get(origin.document)
      : activeNavigationAttempt
    observations.push({
      document: origin.document,
      navigationAbort: cancelledRequest.test(error) && origin.frameInDocument,
      navigationAttempt,
      diagnostic: { ...requestSummary(request), kind: 'requestfailed', message: diagnosticText(error) },
    })
  }

  const onResponse = (response: Response) => {
    const request = response.request()
    const status = response.status()
    const summary = requestSummary(request)
    const headers = response.headers()
    if (request.isNavigationRequest() && mainFrameRequest(request)) {
      applicationId = headers['x-mcweb-application'] || applicationId
      summary.application = applicationId
      documents.push({ ...summary, application: applicationId, status })
      if ((status >= 200 && status < 300) || status === 304) {
        const destinations: string[] = []
        for (let redirected: Request | null = request; redirected; redirected = redirected.redirectedFrom()) {
          const destination = comparableUrl(redirected.url())
          if (destination) destinations.push(destination)
        }
        const destination = comparableUrl(response.url())
        const attempt = navigationAttempts.get(request)
        if (destination && attempt) pendingDocuments.set(destination, { attempt, destinations })
      }
    }
    if (status < 400) return

    // Inertia intentionally uses 409 + X-Inertia-Location to change documents.
    // This is expected only if a same-origin destination actually commits a
    // successful main document. A bare 409 or an uncompleted recovery still fails.
    const target = comparableUrl(headers['x-inertia-location'], response.url())
    const source = comparableUrl(response.url())
    const protocolTarget = status === 409
      && request.headers()['x-inertia'] === 'true'
      && target && source && new URL(target).origin === new URL(source).origin
      ? target
      : undefined
    observations.push({
      document: documentVersion,
      protocolTarget,
      protocolConsoleUrl: protocolTarget ? source ?? undefined : undefined,
      diagnostic: { ...summary, kind: 'http', status, message: `HTTP ${status}` },
    })
  }

  const onFrameNavigated = (frame: Frame) => {
    if (frame !== page.mainFrame()) return
    const destination = comparableUrl(frame.url())
    const pending = destination ? pendingDocuments.get(destination) : undefined
    // Same-document Inertia/history changes must not excuse aborted requests.
    if (!pending) return
    const replacedDocument = documentVersion
    documentVersion += 1
    committedNavigationAttempts.add(pending.attempt)
    replacingNavigationAttempts.set(replacedDocument, pending.attempt)
    for (const url of pending.destinations) committedDocuments.set(url, documentVersion)
    if (activeNavigationAttempt === pending.attempt) activeNavigationAttempt = undefined
    pendingDocuments.clear()
  }

  page.on('request', onRequest)
  page.on('console', onConsole)
  page.on('pageerror', onPageError)
  page.on('requestfailed', onRequestFailed)
  page.on('response', onResponse)
  page.on('framenavigated', onFrameNavigated)

  function report(): BrowserDiagnosticReport {
    const errors: BrowserDiagnostic[] = []
    const expected: BrowserDiagnosticReport['expected'] = []
    const completedProtocols = observations.filter((entry) => entry.protocolTarget
      && (committedDocuments.get(entry.protocolTarget) ?? -1) > entry.document)
    for (const entry of observations) {
      let reason: string | undefined
      if (entry.navigationAbort && entry.navigationAttempt
        && committedNavigationAttempts.has(entry.navigationAttempt)) {
        reason = 'Browser cancelled an old document request during a confirmed document navigation'
      } else if (completedProtocols.includes(entry) || (entry.diagnostic.kind === 'console.error'
        && entry.protocolConsoleUrl && completedProtocols.some((protocol) => (
          protocol.protocolConsoleUrl === entry.protocolConsoleUrl
          && protocol.document === entry.document
        )))) {
        reason = 'Inertia 409 document-location response completed a successful same-origin navigation'
      }
      if (reason) expected.push({ ...entry.diagnostic, reason })
      else errors.push({ ...entry.diagnostic })
    }
    return { errors, expected, documents: documents.map((entry) => ({ ...entry })) }
  }

  function assertClean() {
    const { errors } = report()
    if (errors.length === 0) return
    throw new Error(`Browser diagnostics found ${errors.length} unexpected error(s):\n${errors.map((entry) => (
      `[${entry.application}] ${entry.step} | page=${entry.pageUrl} | ${entry.kind}`
      + `${entry.url ? ` | resource=${entry.url}` : ''} | ${entry.message}`
    )).join('\n')}`)
  }

  function stop() {
    if (!stopped) {
      stopped = true
      page.off('request', onRequest)
      page.off('console', onConsole)
      page.off('pageerror', onPageError)
      page.off('requestfailed', onRequestFailed)
      page.off('response', onResponse)
      page.off('framenavigated', onFrameNavigated)
    }
    return report()
  }

  return {
    report,
    assertClean,
    stop,
    // Set this before navigation/clicking so even timeouts retain a useful step.
    setStep(label: string) { currentStep = label },
  }
}

export type BrowserDiagnostics = ReturnType<typeof captureBrowserDiagnostics>

export async function finishBrowserDiagnostics(
  diagnostics: BrowserDiagnostics,
  attachment?: DiagnosticAttachment,
  name = 'browser-diagnostics',
) {
  const report = diagnostics.stop()
  const failures: unknown[] = []
  try {
    await attachment?.attach(name, {
      body: JSON.stringify(report, null, 2),
      contentType: 'application/json',
    })
  } catch (error) {
    failures.push(error)
  }
  try {
    diagnostics.assertClean()
  } catch (error) {
    failures.push(error)
  }
  if (failures.length === 1) throw failures[0]
  if (failures.length > 1) {
    throw new AggregateError(failures, failures.map((error) => diagnosticText(String(error))).join('\n'))
  }
}

export async function withBrowserDiagnostics<T>(
  page: Page,
  options: Parameters<typeof captureBrowserDiagnostics>[1],
  action: (diagnostics: BrowserDiagnostics) => Promise<T>,
  attachment?: DiagnosticAttachment,
  name?: string,
): Promise<T> {
  const diagnostics = captureBrowserDiagnostics(page, options)
  let result: T | undefined
  const failures: unknown[] = []
  try {
    result = await action(diagnostics)
  } catch (error) {
    failures.push(error)
  }
  try {
    await finishBrowserDiagnostics(diagnostics, attachment, name)
  } catch (error) {
    failures.push(error)
  }
  if (failures.length === 1) throw failures[0]
  if (failures.length > 1) {
    throw new AggregateError(failures,
      `Browser action and diagnostics both failed:\n${failures.map((error) => diagnosticText(String(error))).join('\n')}`,
    )
  }
  return result as T
}
