import type { ConsoleMessage, Frame, Page, Request, Response, TestInfo } from '@playwright/test'

import {
  CONTROLLED_REQUEST_CANCELLATION_BINDING,
  CONTROLLED_REQUEST_CANCELLATION_REASONS,
  CONTROLLED_REQUEST_ID_HEADER,
  type ControlledRequestCancellationEvent,
  type ControlledRequestCancellationReason,
} from '../../../app/javascript/lib/controlledRequestCancellation.ts'

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
  expectedCancellationReason?: string
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

export type ControlledRequestCancellationRule = {
  application: string
  description: string
  method: string
  pathname: RegExp
  reasons: readonly ControlledRequestCancellationReason[]
}

export type ExpectedRequestCancellationRule = {
  application: string
  description: string
  method: string
  pathname: RegExp
}

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
const controlledRequestId = /^v1\.[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
const controlledRequestIdHeader = CONTROLLED_REQUEST_ID_HEADER.toLowerCase()
const controlledCancellationReasons = new Set<string>(CONTROLLED_REQUEST_CANCELLATION_REASONS)

function controlledCancellationEvent(value: unknown): value is ControlledRequestCancellationEvent {
  if (!value || typeof value !== 'object') return false
  const event = value as Partial<ControlledRequestCancellationEvent>
  return typeof event.requestId === 'string'
    && controlledRequestId.test(event.requestId)
    && typeof event.reason === 'string'
    && controlledCancellationReasons.has(event.reason)
}

function requestPathname(value: string): string | null {
  try {
    const url = new URL(value)
    return ['http:', 'https:'].includes(url.protocol) ? url.pathname : null
  } catch {
    return null
  }
}

function requestHeader(headers: Record<string, string>, name: string): string | undefined {
  return Object.entries(headers).find(([key]) => key.toLowerCase() === name)?.[1]
}

function matchesPath(pattern: RegExp, pathname: string): boolean {
  pattern.lastIndex = 0
  return pattern.test(pathname)
}

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
  const inFlightRequests = new Set<Request>()
  const navigationAttempts = new WeakMap<Request, number>()
  const observations: Observation[] = []
  const documents: BrowserDiagnosticReport['documents'] = []
  const pendingDocuments = new Map<string, { attempt: number; destinations: string[] }>()
  const committedDocuments = new Map<string, number>()
  const committedNavigationAttempts = new Set<number>()
  const replacingNavigationAttempts = new Map<number, number>()
  const controlledCancellations = new Map<Request, ControlledRequestCancellationReason>()
  const controlledRequestsById = new Map<string, Request>()
  const failedControlledRequests = new Map<Request, { observation: Observation; requestId: string }>()
  const seenControlledRequestIds = new Set<string>()
  const controlledCancellationRules: ControlledRequestCancellationRule[] = []
  const activeExpectedCancellations: Array<ExpectedRequestCancellationRule & {
    requests: Set<Request>
  }> = []
  let installPromise: Promise<void> | undefined

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

  function matchingControlledCancellationRule(
    request: Request,
    reason?: ControlledRequestCancellationReason,
  ): ControlledRequestCancellationRule | undefined {
    const origin = requestContext(request)
    const pathname = requestPathname(request.url())
    if (!pathname) return undefined
    return controlledCancellationRules.find((rule) => (
      rule.application === origin.application
      && rule.method === request.method().toUpperCase()
      && matchesPath(rule.pathname, pathname)
      && (!reason || rule.reasons.includes(reason))
    ))
  }

  const onRequest = (request: Request) => {
    inFlightRequests.add(request)
    requests.set(request, {
      ...context(),
      document: documentVersion,
      frameInDocument: documentFrameRequest(request),
    })
    const requestId = requestHeader(request.headers(), controlledRequestIdHeader)
    if (requestId && controlledRequestId.test(requestId)) {
      if (seenControlledRequestIds.has(requestId)) {
        const originalRequest = controlledRequestsById.get(requestId)
        if (originalRequest) {
          controlledCancellations.delete(originalRequest)
          failedControlledRequests.delete(originalRequest)
        }
        controlledRequestsById.delete(requestId)
      } else {
        seenControlledRequestIds.add(requestId)
        controlledRequestsById.set(requestId, request)
      }
    }
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
    const pathname = requestPathname(request.url())
    const controlledCancellation = controlledCancellations.get(request)
    controlledCancellations.delete(request)
    const requestId = requestHeader(request.headers(), controlledRequestIdHeader)
    const controlledRule = cancelledRequest.test(error) && controlledCancellation
      ? matchingControlledCancellationRule(request, controlledCancellation)
      : undefined
    const expectedCancellation = cancelledRequest.test(error) && pathname && mainFrameRequest(request)
      ? activeExpectedCancellations.find((rule) => (
        rule.requests.has(request)
        && rule.application === origin.application
        && rule.method === request.method().toUpperCase()
        && matchesPath(rule.pathname, pathname)
      ))
      : undefined
    let expectedCancellationReason: string | undefined
    if (expectedCancellation) {
      expectedCancellationReason = diagnosticText(expectedCancellation.description)
    } else if (controlledCancellation && controlledRule) {
      expectedCancellationReason = `${diagnosticText(controlledRule.description)} (${controlledCancellation})`
    }
    inFlightRequests.delete(request)
    for (const rule of activeExpectedCancellations) rule.requests.delete(request)
    const navigationAttempt = origin.document < documentVersion
      ? replacingNavigationAttempts.get(origin.document)
      : activeNavigationAttempt
    const observation: Observation = {
      document: origin.document,
      expectedCancellationReason,
      navigationAbort: cancelledRequest.test(error) && origin.frameInDocument,
      navigationAttempt,
      diagnostic: { ...requestSummary(request), kind: 'requestfailed', message: diagnosticText(error) },
    }
    observations.push(observation)
    if (requestId
      && controlledRequestsById.get(requestId) === request
      && !controlledCancellation
      && !expectedCancellation
      && cancelledRequest.test(error)
      && mainFrameRequest(request)
      && matchingControlledCancellationRule(request)) {
      failedControlledRequests.set(request, { observation, requestId })
    } else if (requestId && controlledRequestsById.get(requestId) === request) {
      controlledRequestsById.delete(requestId)
    }
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

  const onRequestFinished = (request: Request) => {
    inFlightRequests.delete(request)
    controlledCancellations.delete(request)
    failedControlledRequests.delete(request)
    const requestId = requestHeader(request.headers(), controlledRequestIdHeader)
    if (requestId && controlledRequestsById.get(requestId) === request) {
      controlledRequestsById.delete(requestId)
    }
    for (const rule of activeExpectedCancellations) rule.requests.delete(request)
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
  page.on('requestfinished', onRequestFinished)
  page.on('response', onResponse)
  page.on('framenavigated', onFrameNavigated)

  function install(): Promise<void> {
    installPromise ??= page.exposeBinding(
      CONTROLLED_REQUEST_CANCELLATION_BINDING,
      (source, value: unknown) => {
        if (stopped || source.frame !== page.mainFrame() || !controlledCancellationEvent(value)) return false
        const request = controlledRequestsById.get(value.requestId)
        if (!request || controlledCancellations.has(request)) return false
        const controlledRule = matchingControlledCancellationRule(request, value.reason)
        if (!controlledRule) return false
        const failedRequest = failedControlledRequests.get(request)
        if (failedRequest) {
          if (failedRequest.requestId !== value.requestId
            || failedRequest.observation.expectedCancellationReason) return false
          failedRequest.observation.expectedCancellationReason = (
            `${diagnosticText(controlledRule.description)} (${value.reason})`
          )
          failedControlledRequests.delete(request)
          controlledRequestsById.delete(value.requestId)
          return true
        }
        if (!inFlightRequests.has(request) || !mainFrameRequest(request)) return false
        controlledCancellations.set(request, value.reason)
        return true
      },
    ).then(() => undefined)
    return installPromise
  }

  async function flush(): Promise<void> {
    if (!installPromise || stopped) return
    await installPromise
    // The sentinel binding call is ordered after cancellation reports already
    // issued by the main frame. Awaiting it at teardown drains those reports
    // without ever delaying AbortController.abort in application code.
    const acknowledgement = await page.evaluate((bindingName) => {
      const reporter = (globalThis as unknown as Record<string, unknown>)[bindingName]
      if (typeof reporter !== 'function') throw new Error('Controlled cancellation binding is unavailable')
      return reporter(null)
    }, CONTROLLED_REQUEST_CANCELLATION_BINDING)
    if (acknowledgement !== false) {
      throw new Error('Controlled cancellation binding flush was not acknowledged')
    }
    // Reports issued before the sentinel have now been processed. Keep every
    // unmatched failed request as an error and reject any later report.
    for (const [request, pending] of failedControlledRequests) {
      if (controlledRequestsById.get(pending.requestId) === request) {
        controlledRequestsById.delete(pending.requestId)
      }
    }
    failedControlledRequests.clear()
  }

  function registerControlledRequestCancellation(rule: ControlledRequestCancellationRule) {
    if (!rule.application.trim() || !rule.description.trim() || !rule.method.trim()) {
      throw new TypeError('Controlled cancellation rules require application, description, and method')
    }
    if (!rule.reasons.length || rule.reasons.some((reason) => !controlledCancellationReasons.has(reason))) {
      throw new TypeError('Controlled cancellation rules require recognized reasons')
    }
    controlledCancellationRules.push({
      ...rule,
      method: rule.method.toUpperCase(),
      reasons: [...rule.reasons],
    })
  }

  async function withExpectedRequestCancellation<T>(
    rule: ExpectedRequestCancellationRule,
    action: () => Promise<T>,
  ): Promise<T> {
    if (!rule.application.trim() || !rule.description.trim() || !rule.method.trim()) {
      throw new TypeError('Expected cancellation rules require application, description, and method')
    }
    const method = rule.method.toUpperCase()
    // Capture one concrete request before the action. Requests started inside
    // the window, child-frame work, other paths, and other failure kinds remain
    // unexpected, so a broad pathname allowance cannot hide a network fault.
    const pendingRequests = [...inFlightRequests].filter((request) => {
      const origin = requestContext(request)
      const pathname = requestPathname(request.url())
      return pathname
        && mainFrameRequest(request)
        && origin.application === rule.application
        && request.method().toUpperCase() === method
        && matchesPath(rule.pathname, pathname)
    })
    // Zero candidates need no exception, while multiple candidates cannot
    // prove which request the action owns. In both cases the action still runs,
    // but no failed request is excused. Only a unique live Request may be bound.
    const pendingRequest = pendingRequests.length === 1 ? pendingRequests[0] : undefined
    const activeRule = {
      ...rule,
      method,
      requests: new Set(pendingRequest ? [pendingRequest] : []),
    }
    activeExpectedCancellations.push(activeRule)
    try {
      return await action()
    } finally {
      const index = activeExpectedCancellations.indexOf(activeRule)
      if (index >= 0) activeExpectedCancellations.splice(index, 1)
    }
  }

  function report(): BrowserDiagnosticReport {
    const errors: BrowserDiagnostic[] = []
    const expected: BrowserDiagnosticReport['expected'] = []
    const completedProtocols = observations.filter((entry) => entry.protocolTarget
      && (committedDocuments.get(entry.protocolTarget) ?? -1) > entry.document)
    for (const entry of observations) {
      let reason: string | undefined
      if (entry.expectedCancellationReason) {
        reason = entry.expectedCancellationReason
      } else if (entry.navigationAbort && entry.navigationAttempt
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
      page.off('requestfinished', onRequestFinished)
      page.off('response', onResponse)
      page.off('framenavigated', onFrameNavigated)
      inFlightRequests.clear()
      controlledCancellations.clear()
      controlledRequestsById.clear()
      failedControlledRequests.clear()
      seenControlledRequestIds.clear()
      controlledCancellationRules.length = 0
      for (const rule of activeExpectedCancellations) rule.requests.clear()
      activeExpectedCancellations.length = 0
    }
    return report()
  }

  return {
    flush,
    install,
    report,
    assertClean,
    stop,
    registerControlledRequestCancellation,
    withExpectedRequestCancellation,
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
  const failures: unknown[] = []
  try {
    await diagnostics.flush()
  } catch (error) {
    failures.push(error)
  }
  const report = diagnostics.stop()
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
    await diagnostics.install()
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
