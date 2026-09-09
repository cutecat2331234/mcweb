import assert from 'node:assert/strict'
import { EventEmitter } from 'node:events'
import { readFileSync } from 'node:fs'
import test from 'node:test'

import type { Page, Request, Response } from '@playwright/test'

import {
  CONTROLLED_REQUEST_CANCELLATION_BINDING,
  CONTROLLED_REQUEST_ID_HEADER,
  type ControlledRequestCancellationEvent,
} from '../../app/javascript/lib/controlledRequestCancellation.ts'
import {
  captureBrowserDiagnostics,
  diagnosticText,
  diagnosticUrl,
  finishBrowserDiagnostics,
  withBrowserDiagnostics,
} from '../e2e/support/browser-diagnostics.ts'

const origin = 'https://mcweb.test'

class DiagnosticPage extends EventEmitter {
  currentUrl = `${origin}/app/account`
  frame = { url: () => this.currentUrl, parentFrame: () => null }
  bindings = new Map<string, (source: { frame: typeof this.frame }, value: unknown) => unknown>()
  bindingFlushes = 0
  url() { return this.currentUrl }
  mainFrame() { return this.frame }
  asPage() { return this as unknown as Page }

  async exposeBinding(
    name: string,
    callback: (source: { frame: typeof this.frame }, value: unknown) => unknown,
  ) {
    this.bindings.set(name, callback)
  }

  async evaluate(_callback: unknown, bindingName: string) {
    const binding = this.bindings.get(bindingName)
    assert.ok(binding, 'browser diagnostics binding must be installed before it is flushed')
    this.bindingFlushes += 1
    return binding({ frame: this.frame }, null)
  }

  async reportControlledCancellation(event: ControlledRequestCancellationEvent) {
    const binding = this.bindings.get(CONTROLLED_REQUEST_CANCELLATION_BINDING)
    assert.ok(binding, 'browser diagnostics binding must be installed')
    return binding({ frame: this.frame }, event)
  }

  console(type: string, text: string, url = `${origin}/assets/account.js`) {
    this.emit('console', { type: () => type, text: () => text, location: () => ({ url }) })
  }

  request(path: string, {
    resourceType = 'fetch', method = 'GET', headers = {},
    failure = 'net::ERR_FAILED', redirectedFrom = null, childFrame = false, noFrame = false,
  }: {
    resourceType?: string; method?: string; headers?: Record<string, string>
    failure?: string; redirectedFrom?: Request | null; childFrame?: boolean; noFrame?: boolean
  } = {}): Request {
    const request = {
      url: () => new URL(path, origin).href,
      method: () => method,
      resourceType: () => resourceType,
      isNavigationRequest: () => resourceType === 'document',
      headers: () => headers,
      failure: () => ({ errorText: failure }),
      frame: () => {
        if (noFrame) throw new Error('A service worker request has no frame')
        return childFrame ? { parentFrame: () => this.frame } : this.frame
      },
      redirectedFrom: () => redirectedFrom,
    } as unknown as Request
    this.emit('request', request)
    return request
  }

  response(
    request: Request,
    status: number,
    headers: Record<string, string> = {},
    finished = true,
  ) {
    this.emit('response', {
      url: () => request.url(), request: () => request,
      status: () => status, headers: () => headers,
    } as Response)
    if (finished) this.emit('requestfinished', request)
  }

  navigate(path: string, {
    status = 200, application = 'account', redirectedFrom = null,
  }: { status?: number; application?: string; redirectedFrom?: Request | null } = {}) {
    const request = this.request(path, { resourceType: 'document', redirectedFrom })
    this.response(request, status, { 'x-mcweb-application': application })
    this.currentUrl = request.url()
    this.emit('framenavigated', this.frame)
  }
}

function monitoredPage() {
  const page = new DiagnosticPage()
  const diagnostics = captureBrowserDiagnostics(page.asPage(), { application: 'account', step: 'Open account' })
  return { page, diagnostics }
}

test('all console errors and uncaught exceptions fail with application, step, and page URL', () => {
  const { page, diagnostics } = monitoredPage()
  diagnostics.setStep('Open security')
  page.console('error', '[McWeb I18N] Missing translation: locale=en key=identity.security.title')
  page.console('error', '[McWeb] account rendering failed')
  page.emit('pageerror', new Error('Unhandled promise rejection'))

  assert.deepEqual(diagnostics.report().errors.map((entry) => entry.kind), [
    'console.error', 'console.error', 'pageerror',
  ])
  assert.throws(() => diagnostics.assertClean(), /\[account\] Open security \| page=https:\/\/mcweb.test\/app\/account/)
  assert.throws(() => diagnostics.assertClean(), /Missing translation/)
  assert.throws(() => diagnostics.assertClean(), /Unhandled promise rejection/)
})

test('broken Vue and translation contracts fail without promoting generic browser notices to errors', () => {
  const { page, diagnostics } = monitoredPage()
  for (const message of [
    '[Vue warn]: Invalid prop: type check failed for prop "value".',
    '[Vue warn]: Missing required prop: "model"',
    '[Vue warn]: Failed to resolve component: UnknownButton',
    '[Vue warn]: Extraneous non-props attributes (value) were passed to component',
    '[Vue warn]: Hydration node mismatch',
    '[intlify] Not found \'account.title\' key in \'en\' locale messages.',
  ]) page.console('warning', message)
  page.console('warning', 'This API is deprecated; see browser documentation')
  page.console('info', 'Install the Vue devtools extension')
  page.console('log', 'Background job completed')
  assert.equal(diagnostics.report().errors.length, 6)
  assert.ok(diagnostics.report().errors.every((entry) => entry.kind === 'framework.warning'))
})

test('failed assets, fetches, child-frame requests, and main documents are all observable', () => {
  const { page, diagnostics } = monitoredPage()
  for (const resourceType of ['script', 'stylesheet', 'image', 'font', 'fetch', 'document']) {
    const request = page.request(`/broken-${resourceType}`, { resourceType })
    page.emit('requestfailed', request)
  }
  page.emit('requestfailed', page.request('/iframe.js', { childFrame: true }))
  const report = diagnostics.report()
  assert.equal(report.errors.length, 7)
  assert.ok(report.errors.every((entry) => entry.kind === 'requestfailed'))
  assert.throws(() => diagnostics.assertClean(), /net::ERR_FAILED/)
})

test('late resource failures retain the application and step where the request started', () => {
  const { page, diagnostics } = monitoredPage()
  const request = page.request('/assets/account.js')
  diagnostics.setStep('Open Admin')
  page.navigate('/admin', { application: 'admin' })
  page.emit('requestfailed', request)
  page.console('error', 'Admin rendering failed')
  const [account, admin] = diagnostics.report().errors
  assert.equal(account.application, 'account')
  assert.equal(account.step, 'Open account')
  assert.equal(admin.application, 'admin')
  assert.equal(admin.step, 'Open Admin')
})

test('HTTP failures are caught even when the browser does not emit a console error', () => {
  const { page, diagnostics } = monitoredPage()
  page.navigate('/admin', { status: 503, application: 'admin' })
  page.response(page.request('/assets/admin.css', { resourceType: 'stylesheet' }), 404)
  page.response(page.request('/admin/data'), 422)
  page.response(page.request('/healthy'), 200)
  page.response(page.request('/cached'), 304)
  assert.deepEqual(diagnostics.report().errors.map((entry) => entry.status), [503, 404, 422])
  assert.equal(diagnostics.report().documents[0].status, 503)
})

test('same-document cancellation is not globally ignored as net::ERR_ABORTED', () => {
  const { page, diagnostics } = monitoredPage()
  page.emit('requestfailed', page.request('/account/data', { failure: 'net::ERR_ABORTED' }))
  page.currentUrl = `${origin}/app/identity/security`
  page.emit('framenavigated', page.frame)
  assert.equal(diagnostics.report().errors.length, 1)
  assert.equal(diagnostics.report().expected.length, 0)
})

test('a registered cancellation binds one exact live request and is consumed once', async () => {
  const { page, diagnostics } = monitoredPage()
  await diagnostics.install()
  diagnostics.registerControlledRequestCancellation({
    application: 'account',
    description: 'Account background refresh was cancelled after its deadline',
    method: 'POST',
    pathname: /^\/app\/account\/refresh$/,
    reasons: ['deadline_exceeded'],
  })
  const requestId = 'v1.00000000-0000-4000-8000-000000000001'
  const event = { requestId, reason: 'deadline_exceeded' as const }
  assert.equal(await page.reportControlledCancellation(event), false, 'a report cannot precede its request')

  const request = page.request('/app/account/refresh', {
    method: 'POST',
    failure: 'net::ERR_ABORTED',
    headers: { [CONTROLLED_REQUEST_ID_HEADER.toLowerCase()]: requestId },
  })
  assert.equal(await page.reportControlledCancellation(event), true)
  assert.equal(await page.reportControlledCancellation(event), false, 'one request accepts one report')
  page.emit('requestfailed', request)

  assert.equal(diagnostics.report().errors.length, 0)
  assert.equal(diagnostics.report().expected.length, 1)
  assert.match(diagnostics.report().expected[0]!.reason, /deadline_exceeded/)

  const replay = page.request('/app/account/refresh', {
    method: 'POST',
    failure: 'net::ERR_ABORTED',
    headers: { [CONTROLLED_REQUEST_ID_HEADER.toLowerCase()]: requestId },
  })
  assert.equal(
    await page.reportControlledCancellation(event),
    false,
    'a consumed request ID cannot be replayed onto another live request',
  )
  page.emit('requestfailed', replay)
  assert.equal(
    await page.reportControlledCancellation(event),
    false,
    'a replay report arriving after requestfailed cannot excuse a reused request ID',
  )
  assert.equal(diagnostics.report().expected.length, 1)
  assert.equal(diagnostics.report().errors.length, 1)
})

test('a cancellation report racing after requestfailed is reconciled before flush', async () => {
  const { page, diagnostics } = monitoredPage()
  await diagnostics.install()
  diagnostics.registerControlledRequestCancellation({
    application: 'account',
    description: 'Account background refresh was cancelled after its deadline',
    method: 'POST',
    pathname: /^\/app\/account\/refresh$/,
    reasons: ['deadline_exceeded'],
  })
  const requestId = 'v1.00000000-0000-4000-8000-000000000010'
  const event = { requestId, reason: 'deadline_exceeded' as const }
  const request = page.request('/app/account/refresh', {
    method: 'POST',
    failure: 'net::ERR_ABORTED',
    headers: { [CONTROLLED_REQUEST_ID_HEADER.toLowerCase()]: requestId },
  })

  page.emit('requestfailed', request)
  assert.equal(diagnostics.report().errors.length, 1)
  assert.equal(await page.reportControlledCancellation(event), true)
  await diagnostics.flush()

  assert.equal(diagnostics.report().errors.length, 0)
  assert.equal(diagnostics.report().expected.length, 1)
  assert.match(diagnostics.report().expected[0]!.reason, /deadline_exceeded/)
  assert.equal(await page.reportControlledCancellation(event), false, 'a late report is consumed once')
})

test('flush leaves an unmatched failed request visible and closes its correlation window', async () => {
  const { page, diagnostics } = monitoredPage()
  await diagnostics.install()
  diagnostics.registerControlledRequestCancellation({
    application: 'account',
    description: 'Account background refresh was cancelled after its deadline',
    method: 'POST',
    pathname: /^\/app\/account\/refresh$/,
    reasons: ['deadline_exceeded'],
  })
  const requestId = 'v1.00000000-0000-4000-8000-000000000011'
  const event = { requestId, reason: 'deadline_exceeded' as const }
  const request = page.request('/app/account/refresh', {
    method: 'POST',
    failure: 'net::ERR_ABORTED',
    headers: { [CONTROLLED_REQUEST_ID_HEADER.toLowerCase()]: requestId },
  })

  page.emit('requestfailed', request)
  await diagnostics.flush()

  assert.equal(await page.reportControlledCancellation(event), false)
  assert.equal(diagnostics.report().expected.length, 0)
  assert.equal(diagnostics.report().errors.length, 1)
})

test('flush closes correlation for a request that is still in flight', async () => {
  const { page, diagnostics } = monitoredPage()
  await diagnostics.install()
  diagnostics.registerControlledRequestCancellation({
    application: 'account',
    description: 'Account background refresh was cancelled after its deadline',
    method: 'POST',
    pathname: /^\/app\/account\/refresh$/,
    reasons: ['deadline_exceeded'],
  })
  const requestId = 'v1.00000000-0000-4000-8000-000000000012'
  const event = { requestId, reason: 'deadline_exceeded' as const }
  const request = page.request('/app/account/refresh', {
    method: 'POST',
    failure: 'net::ERR_ABORTED',
    headers: { [CONTROLLED_REQUEST_ID_HEADER.toLowerCase()]: requestId },
  })

  await diagnostics.flush()
  assert.equal(await page.reportControlledCancellation(event), false)
  page.emit('requestfailed', request)

  assert.equal(diagnostics.report().expected.length, 0)
  assert.equal(diagnostics.report().errors.length, 1)
})

test('a cancellation report cannot choose between duplicate in-flight request IDs', async () => {
  const { page, diagnostics } = monitoredPage()
  await diagnostics.install()
  diagnostics.registerControlledRequestCancellation({
    application: 'account',
    description: 'Account background refresh was cancelled after its deadline',
    method: 'POST',
    pathname: /^\/app\/account\/refresh$/,
    reasons: ['deadline_exceeded'],
  })
  const requestId = 'v1.00000000-0000-4000-8000-000000000009'
  const options = {
    method: 'POST',
    failure: 'net::ERR_ABORTED',
    headers: { [CONTROLLED_REQUEST_ID_HEADER.toLowerCase()]: requestId },
  }
  const first = page.request('/app/account/refresh', options)
  const second = page.request('/app/account/refresh', options)

  assert.equal(
    await page.reportControlledCancellation({ requestId, reason: 'deadline_exceeded' }),
    false,
  )
  page.emit('requestfailed', first)
  page.emit('requestfailed', second)
  assert.equal(diagnostics.report().expected.length, 0)
  assert.equal(diagnostics.report().errors.length, 2)
})

test('controlled cancellation never hides an unregistered route, reason, or real network failure', async () => {
  const { page, diagnostics } = monitoredPage()
  await diagnostics.install()
  diagnostics.registerControlledRequestCancellation({
    application: 'account',
    description: 'Registered account refresh',
    method: 'POST',
    pathname: /^\/app\/account\/refresh$/,
    reasons: ['component_unmounted'],
  })

  const cases = [
    { id: 2, path: '/app/account/other', reason: 'component_unmounted' as const, failure: 'net::ERR_ABORTED' },
    { id: 3, path: '/app/account/refresh', reason: 'deadline_exceeded' as const, failure: 'net::ERR_ABORTED' },
    { id: 4, path: '/app/account/refresh', reason: 'component_unmounted' as const, failure: 'net::ERR_CONNECTION_REFUSED' },
  ]
  for (const entry of cases) {
    const requestId = `v1.00000000-0000-4000-8000-${String(entry.id).padStart(12, '0')}`
    const request = page.request(entry.path, {
      method: 'POST',
      failure: entry.failure,
      headers: { [CONTROLLED_REQUEST_ID_HEADER.toLowerCase()]: requestId },
    })
    assert.equal(
      await page.reportControlledCancellation({ requestId, reason: entry.reason }),
      entry.id === 4,
    )
    page.emit('requestfailed', request)
  }

  assert.equal(diagnostics.report().expected.length, 0)
  assert.equal(diagnostics.report().errors.length, cases.length)
  assert.throws(() => diagnostics.assertClean(), /ERR_CONNECTION_REFUSED/)
})

test('a test-owned cancellation scope keeps a response-body request exact and one-shot', async () => {
  const { page, diagnostics } = monitoredPage()
  const pendingRequest = page.request('/app/account', { failure: 'net::ERR_ABORTED' })
  page.response(pendingRequest, 200, {}, false)
  await diagnostics.withExpectedRequestCancellation({
    application: 'account',
    description: 'Acceptance replaced one pending account read with a document navigation',
    method: 'GET',
    pathname: /^\/app\/account$/,
  }, async () => {
    page.emit('requestfailed', page.request('/app/account', {
      failure: 'net::ERR_CONNECTION_REFUSED',
    }))
    page.emit('requestfailed', page.request('/app/account', {
      failure: 'net::ERR_ABORTED',
      childFrame: true,
    }))
    page.emit('requestfailed', page.request('/app/account', { failure: 'net::ERR_ABORTED' }))
    page.emit('requestfailed', pendingRequest)
    page.emit('requestfailed', page.request('/app/account', { failure: 'net::ERR_ABORTED' }))
    page.emit('requestfailed', page.request('/app/other', { failure: 'net::ERR_ABORTED' }))
  })
  page.emit('requestfailed', page.request('/app/account', { failure: 'net::ERR_ABORTED' }))

  assert.equal(diagnostics.report().expected.length, 1)
  assert.equal(diagnostics.report().errors.length, 6)
})

test('a test-owned cancellation scope fails closed when multiple live requests match', async () => {
  const { page, diagnostics } = monitoredPage()
  const first = page.request('/app/account', { failure: 'net::ERR_ABORTED' })
  const second = page.request('/app/account', { failure: 'net::ERR_ABORTED' })

  await diagnostics.withExpectedRequestCancellation({
    application: 'account',
    description: 'Acceptance replaced one pending account read with a document navigation',
    method: 'GET',
    pathname: /^\/app\/account$/,
  }, async () => {
    page.emit('requestfailed', first)
    page.emit('requestfailed', second)
  })

  assert.equal(diagnostics.report().expected.length, 0)
  assert.equal(diagnostics.report().errors.length, 2)
})

test('cancelled old document resources become expected only after a confirmed successful document navigation', () => {
  const { page, diagnostics } = monitoredPage()
  const requests = ['script', 'stylesheet', 'image', 'fetch', 'document'].map((resourceType) => (
    page.request(`/old-${resourceType}`, { resourceType, failure: 'net::ERR_ABORTED' })
  ))
  const childRequest = page.request('/child-frame-data', { failure: 'net::ERR_ABORTED', childFrame: true })
  const workerRequest = page.request('/worker-data', { noFrame: true })
  const realFailure = page.request('/real-network-error', { failure: 'net::ERR_CONNECTION_REFUSED' })
  const navigation = page.request('/admin', { resourceType: 'document' })

  for (const request of requests) {
    page.emit('requestfailed', request)
  }
  page.emit('requestfailed', realFailure)
  page.emit('requestfailed', childRequest)
  page.emit('requestfailed', workerRequest)
  page.response(navigation, 200, { 'x-mcweb-application': 'admin' })
  page.currentUrl = navigation.url()
  page.emit('framenavigated', page.frame)

  assert.equal(diagnostics.report().expected.length, 6)
  assert.equal(diagnostics.report().errors.length, 2)
  assert.throws(() => diagnostics.assertClean(), /ERR_CONNECTION_REFUSED/)
})

test('an earlier abort is not excused by an unrelated later document navigation', () => {
  const { page, diagnostics } = monitoredPage()
  for (const resourceType of ['script', 'stylesheet', 'image', 'fetch', 'document']) {
    page.emit('requestfailed', page.request(`/old-${resourceType}`, { resourceType, failure: 'net::ERR_ABORTED' }))
  }
  page.navigate('/admin', { application: 'admin' })
  assert.equal(diagnostics.report().expected.length, 0)
  assert.equal(diagnostics.report().errors.length, 5)
})

test('a late abort from the replaced document remains tied to its successful navigation', () => {
  const { page, diagnostics } = monitoredPage()
  const oldRequest = page.request('/slow-account-resource', { failure: 'net::ERR_ABORTED' })
  page.navigate('/admin', { application: 'admin' })
  page.emit('requestfailed', oldRequest)
  assert.equal(diagnostics.report().expected.length, 1)
  assert.equal(diagnostics.report().errors.length, 0)
})

test('an aborted request is not excused by an HTTP error document', () => {
  const { page, diagnostics } = monitoredPage()
  page.emit('requestfailed', page.request('/cancelled', { failure: 'net::ERR_ABORTED' }))
  page.navigate('/admin', { status: 500 })
  assert.equal(diagnostics.report().errors.length, 2)
  assert.equal(diagnostics.report().expected.length, 0)
})

test('bare 409s, missing Inertia request headers, cross-origin locations, and incomplete handoffs fail', () => {
  const { page, diagnostics } = monitoredPage()
  page.response(page.request('/bare-conflict'), 409)
  page.response(page.request('/missing-location', { headers: { 'x-inertia': 'true' } }), 409)
  page.response(page.request('/not-inertia'), 409, { 'x-inertia-location': '/admin' })
  page.response(page.request('/external', { headers: { 'x-inertia': 'true' } }), 409, { 'x-inertia-location': 'https://elsewhere.test/admin' })
  page.response(page.request('/unfinished', { headers: { 'x-inertia': 'true' } }), 409, { 'x-inertia-location': '/admin' })
  assert.equal(diagnostics.report().errors.length, 5)
  assert.equal(diagnostics.report().expected.length, 0)
})

test('an Inertia 409 and its exact browser network message remain reported as an expected completed handoff', () => {
  const { page, diagnostics } = monitoredPage()
  const request = page.request('/app/identity/session', { method: 'POST', headers: { 'x-inertia': 'true' } })
  page.response(request, 409, { 'x-inertia-location': '/app' })
  page.console('error', 'Failed to load resource: the server responded with a status of 409 (Conflict)', request.url())
  const launcher = page.request('/app', { resourceType: 'document' })
  page.response(launcher, 302)
  page.navigate('/app/account', { redirectedFrom: launcher })

  assert.equal(diagnostics.report().errors.length, 0)
  assert.equal(diagnostics.report().expected.length, 2)
  assert.equal(diagnostics.report().documents.length, 2)
  assert.doesNotThrow(() => diagnostics.assertClean())
})

test('application errors mentioning 409 and unrelated 409 resource errors are never hidden by a handoff', () => {
  const { page, diagnostics } = monitoredPage()
  const request = page.request('/handoff', { headers: { 'x-inertia': 'true' } })
  page.response(request, 409, { 'x-inertia-location': '/admin' })
  page.console('error', 'Application failed after status of 409', request.url())
  page.console('error', 'Failed to load resource: the server responded with a status of 409 (Conflict)', `${origin}/another-resource`)
  page.navigate('/admin', { application: 'admin' })
  assert.equal(diagnostics.report().expected.length, 1)
  assert.equal(diagnostics.report().errors.length, 2)
})

test('diagnostic URLs and messages do not retain URL credentials, signed queries, or labelled secrets', () => {
  assert.equal(diagnosticUrl('https://user:password@mcweb.test/admin?token=secret#private'), `${origin}/admin`)
  assert.equal(diagnosticUrl('data:text/plain,secret'), '(non-http document)')
  const value = diagnosticText('Failed https://user:password@mcweb.test/asset?signature=secret#fragment password="hidden" csrf_token=hidden')
  assert.doesNotMatch(value, /user:|signature=|fragment|hidden/)
  assert.match(value, /password=\[redacted\]/)
  assert.doesNotMatch(diagnosticText('Authorization: Bearer private-value'), /private-value/)
  assert.doesNotMatch(diagnosticText('Cookie: first=private; second=private'), /private/)
  for (const [input, expected] of [
    ['/app/identity/password_resets/reset-token/edit', '/app/identity/password_resets/[redacted]/edit'],
    ['/app/identity/security/totp/recovery/recovery-token', '/app/identity/security/totp/recovery/[redacted]'],
    ['/app/store/compare/share-token', '/app/store/compare/[redacted]'],
    ['/app/store/wishlist/share-token', '/app/store/wishlist/[redacted]'],
    ['/app/store/downloads/download-token', '/app/store/downloads/[redacted]'],
    ['/minecraft/sync/signed-token', '/minecraft/sync/[redacted]'],
  ]) {
    assert.equal(diagnosticUrl(`${origin}${input}?token=hidden`), `${origin}${expected}`)
  }
  for (const path of [
    '/app/identity/password_resets/new',
    '/app/identity/security/totp/recovery/new',
    '/app/store/compare/toggle',
    '/app/store/compare/import_wishlist',
    '/app/store/wishlist/filter_presets',
    '/app/store/wishlist/share',
    '/app/store/wishlist/add_all_to_cart',
  ]) assert.equal(diagnosticUrl(`${origin}${path}`), `${origin}${path}`)
})

test('stopping is idempotent, removes every listener, and cannot clear earlier errors', () => {
  const { page, diagnostics } = monitoredPage()
  page.console('error', 'Before stop')
  const initial = diagnostics.stop()
  diagnostics.stop()
  assert.equal(page.eventNames().length, 0)
  page.console('error', 'After stop')
  assert.deepEqual(diagnostics.report(), initial)
  assert.throws(() => diagnostics.assertClean(), /Before stop/)
})

test('teardown attaches errors even when the action fails and preserves both failures', async () => {
  const page = new DiagnosticPage()
  const actionFailure = new Error('The CMS menu click timed out')
  const attachments: string[] = []
  await assert.rejects(withBrowserDiagnostics(page.asPage(), { application: 'admin', step: 'Click CMS menu' }, async () => {
    page.console('error', 'The CMS component failed')
    throw actionFailure
  }, {
    async attach(_name, options) { attachments.push(String(options?.body)) },
  }), (error: unknown) => {
    assert.ok(error instanceof AggregateError)
    assert.equal(error.errors[0], actionFailure)
    assert.match(String(error.errors[1]), /CMS component failed/)
    return true
  })
  assert.equal(attachments.length, 1)
  assert.match(attachments[0], /CMS component failed/)
  assert.equal(page.bindingFlushes, 1)
  assert.equal(page.eventNames().length, 0)
})

test('an attachment failure cannot turn a browser error into a pass', async () => {
  const { page, diagnostics } = monitoredPage()
  page.console('error', 'Never swallow this error')
  await assert.rejects(finishBrowserDiagnostics(diagnostics, {
    async attach() { throw new Error('Attachment output unavailable') },
  }), /Never swallow this error/)
})

test('CE app, Admin, CMS, sign-in interface, and manual auth setup use the shared guard', () => {
  for (const spec of ['account-quality', 'admin-quality', 'admin-website-navigation', 'auth-interface-quality']) {
    const source = readFileSync(new URL(`../e2e/${spec}.spec.ts`, import.meta.url), 'utf8')
    assert.match(source, /from '\.\/support\/fixtures'/)
    assert.doesNotMatch(source, /function captureDiagnostics|const consoleErrors/)
  }
  const fixture = readFileSync(new URL('../e2e/support/fixtures.ts', import.meta.url), 'utf8')
  assert.match(fixture, /auto: true/)
  assert.match(fixture, /await diagnostics\.install\(\)/)
  assert.match(fixture, /finally\s*\{[\s\S]*finishBrowserDiagnostics/)
  const auth = readFileSync(new URL('../e2e/support/auth-state.ts', import.meta.url), 'utf8')
  assert.match(auth, /await withBrowserDiagnostics\(page,/)
  assert.match(auth, /diagnosticsAttachment, `browser-diagnostics-sign-in-/)
})
