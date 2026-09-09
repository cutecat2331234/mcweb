import assert from 'node:assert/strict'
import { EventEmitter } from 'node:events'
import { readFileSync } from 'node:fs'
import test from 'node:test'

import type { Page, Request, Response } from '@playwright/test'

import {
  acceptanceSignInDocumentLocation,
  hasSuccessfulSignInDocumentHandoff,
  submitAcceptanceSignIn,
} from '../e2e/support/sign-in-navigation.ts'

const origin = 'https://mcweb.test'
const frame = {}

function responseFor(path: string, {
  status = 200, location, inertia = false, document = false, childFrame = false, redirectedFrom = null,
}: {
  status?: number; location?: string; inertia?: boolean; document?: boolean
  childFrame?: boolean; redirectedFrom?: Request | null
} = {}): Response {
  const url = new URL(path, origin).href
  const request = {
    url: () => url,
    headers: () => inertia ? { 'x-inertia': 'true' } : {},
    isNavigationRequest: () => document,
    frame: () => childFrame ? {} : frame,
    redirectedFrom: () => redirectedFrom,
  } as unknown as Request
  return {
    url: () => url,
    status: () => status,
    headers: () => location ? { 'x-inertia-location': location } : {},
    request: () => request,
  } as Response
}

function pageAt(path: string): Page {
  return { url: () => new URL(path, origin).href, mainFrame: () => frame } as unknown as Page
}

test('ordinary sign-in redirects remain valid without a document-location response', () => {
  assert.equal(acceptanceSignInDocumentLocation(responseFor('/app/identity/session', { status: 303 }), 'owner'), null)
})

test('sign-in recognizes only the standard same-origin Inertia document-location contract', () => {
  const response = responseFor('/app/identity/session', {
    status: 409, inertia: true, location: '/app/forum/latest?locale=en#latest',
  })
  assert.equal(acceptanceSignInDocumentLocation(response, 'owner'), `${origin}/app/forum/latest?locale=en`)
})

test('bare conflicts, non-Inertia responses, external locations, and login failures still fail', () => {
  for (const options of [
    { status: 409 },
    { status: 409, location: '/app/account' },
    { status: 409, inertia: true },
    { status: 409, inertia: true, location: 'https://elsewhere.test/app/account' },
    { status: 409, inertia: true, location: 'https://secret:password@mcweb.test/app/account' },
    { status: 409, inertia: true, location: 'javascript:alert(1)' },
    { status: 409, inertia: true, location: '/app/\\account' },
    { status: 422, inertia: true, location: '/app/account' },
    { status: 429 },
    { status: 500 },
  ]) {
    assert.throws(
      () => acceptanceSignInDocumentLocation(responseFor('/app/identity/session', options), 'owner'),
      /without a valid document handoff/,
    )
  }
})

test('a successful direct main document confirms a sign-in handoff', () => {
  const target = `${origin}/app/forum/latest`
  const response = responseFor(target, { document: true })
  assert.equal(hasSuccessfulSignInDocumentHandoff(pageAt(target), target, [response]), true)
})

test('the successful final document may follow same-origin launcher redirects', () => {
  const launcher = responseFor('/app', { status: 302, document: true })
  const final = responseFor('/app/account', { document: true, redirectedFrom: launcher.request() })
  assert.equal(hasSuccessfulSignInDocumentHandoff(pageAt('/app/account'), `${origin}/app`, [launcher, final]), true)
})

test('a matching SPA URL, child frame, failed document, or unrelated document cannot confirm the handoff', () => {
  const target = `${origin}/app/forum/latest`
  for (const responses of [
    [],
    [responseFor(target)],
    [responseFor(target, { document: true, childFrame: true })],
    [responseFor(target, { document: true, status: 500 })],
    [responseFor('/app/account', { document: true })],
  ]) assert.equal(hasSuccessfulSignInDocumentHandoff(pageAt(target), target, responses), false)

  assert.equal(hasSuccessfulSignInDocumentHandoff(pageAt('/app/account'), target, [
    responseFor(target, { document: true }),
  ]), false)
})

test('a same-origin handoff that redirects to an external final document still fails', () => {
  const launcher = responseFor('/app', { status: 302, document: true })
  const final = responseFor('https://elsewhere.test/app/account', {
    document: true, redirectedFrom: launcher.request(),
  })
  assert.equal(hasSuccessfulSignInDocumentHandoff(
    pageAt('https://elsewhere.test/app/account'), `${origin}/app`, [launcher, final],
  ), false)
})

test('a handoff cannot leave the origin and return through an external intermediate redirect', () => {
  const launcher = responseFor('/app', { status: 302, document: true })
  const external = responseFor('https://elsewhere.test/return', {
    status: 302, document: true, redirectedFrom: launcher.request(),
  })
  const final = responseFor('/app/account', {
    document: true, redirectedFrom: external.request(),
  })
  assert.equal(hasSuccessfulSignInDocumentHandoff(
    pageAt('/app/account'), `${origin}/app`, [launcher, external, final],
  ), false)
})

test('fast handoffs are observed before the click resolves and listeners are always removed', async () => {
  for (const completesDocument of [true, false]) {
    const events = new EventEmitter()
    const target = '/app/forum/latest'
    const signIn = responseFor('/app/identity/session', { status: 409, inertia: true, location: target })
    const landing = responseFor(target, { document: true })
    let releaseResponse: (response: Response) => void = () => {}
    const page = {
      on: events.on.bind(events),
      off: events.off.bind(events),
      mainFrame: () => frame,
      url: () => new URL(target, origin).href,
      waitForResponse: () => new Promise<Response>((resolve) => { releaseResponse = resolve }),
      waitForURL: async () => {},
      getByRole: () => ({
        click: async () => {
          if (completesDocument) events.emit('response', landing)
          releaseResponse(signIn)
        },
      }),
    } as unknown as Page

    if (completesDocument) await submitAcceptanceSignIn(page, 'owner')
    else await assert.rejects(submitAcceptanceSignIn(page, 'owner'), /did not complete/)
    assert.equal(events.listenerCount('response'), 0)
  }
})

test('both real UI sign-in helpers use the same checked document handoff', () => {
  for (const file of ['auth-state', 'session']) {
    const source = readFileSync(new URL(`../e2e/support/${file}.ts`, import.meta.url), 'utf8')
    assert.match(source, /await submitAcceptanceSignIn\(page,/)
    assert.doesNotMatch(source, /response\.status\(\).*400/)
  }
  const source = readFileSync(new URL('../e2e/support/sign-in-navigation.ts', import.meta.url), 'utf8')
  assert.ok(source.indexOf("page.on('response', onResponse)") < source.indexOf("getByRole('button'"))
  assert.match(source, /finally\s*\{\s*page\.off\('response', onResponse\)/)
})
