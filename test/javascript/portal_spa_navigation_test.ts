import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

import { resolvePortalSpaHref } from '../../app/javascript/lib/portalNavigation.ts'

const currentHref = 'https://mcweb.test/app/forum/topics/topic_example'

test('same-origin app destinations stay inside the portal Inertia entry', () => {
  assert.equal(
    resolvePortalSpaHref({
      href: '/app/forum/sections?category=general#latest',
      currentHref,
    }),
    '/app/forum/sections?category=general#latest',
  )
  assert.equal(
    resolvePortalSpaHref({
      href: 'https://mcweb.test/app/chat?space=2',
      currentHref,
    }),
    '/app/chat?space=2',
  )
})

test('cross-entry and explicitly native destinations retain browser navigation', () => {
  for (const options of [
    { href: '/admin', currentHref },
    { href: '/', currentHref },
    { href: 'https://example.com/app/forum/sections', currentHref },
    { href: '/app/forum/export.csv', currentHref, download: true },
    { href: '/app/forum/sections', currentHref, target: '_blank' },
    { href: '/app/forum/sections', currentHref, hardNavigation: true },
    { href: '#post-20', currentHref },
  ]) {
    assert.equal(resolvePortalSpaHref(options), null)
  }
})

test('portal entry installs delegated navigation for links inside rendered rich text', () => {
  const entry = readFileSync(
    new URL('../../app/javascript/entrypoints/inertia.ts', import.meta.url),
    'utf8',
  )
  const navigation = readFileSync(
    new URL('../../app/javascript/lib/portalNavigation.ts', import.meta.url),
    'utf8',
  )

  assert.match(entry, /installPortalSpaNavigation\(\(href\) => router\.visit\(href\)\)/)
  assert.match(navigation, /target\.closest<HTMLAnchorElement>\('a\[href\]'\)/)
  assert.match(navigation, /destinationUrl\.pathname\.startsWith\('\/app\/'\)/)
})

test('portal return-to-website action opens a separate browser tab', () => {
  const sidebar = readFileSync(
    new URL('../../app/javascript/components/portal/PortalSidebar.vue', import.meta.url),
    'utf8',
  )

  const returnLink = sidebar.match(/<a\s+:href="routes\.home"[\s\S]*?<\/a>/)?.[0] || ''
  assert.match(returnLink, /target="_blank"/)
  assert.match(returnLink, /rel="noopener noreferrer"/)
  assert.match(returnLink, /data-no-prefetch/)
  assert.match(returnLink, /portal\.backToWebsite/)
})

test('portal prefetch is delayed, protocol-aware, and explicit safe opt-in only', () => {
  const entry = readFileSync(
    new URL('../../app/javascript/entrypoints/inertia.ts', import.meta.url),
    'utf8',
  )
  const prefetch = readFileSync(
    new URL('../../app/javascript/lib/intentPrefetch.ts', import.meta.url),
    'utf8',
  )

  assert.match(entry, /installIntentPrefetch\(\)/)
  assert.match(prefetch, /DEFAULT_HOVER_DELAY = 150/)
  assert.match(prefetch, /router\.prefetch\(/)
  assert.match(prefetch, /localeRequestHeaders\(\)/)
  assert.match(prefetch, /router\.getCached\(href, visitOptions\)/)
  assert.match(prefetch, /router\.getPrefetching\(href, visitOptions\)/)
  assert.match(prefetch, /connection\.saveData/)
  assert.match(prefetch, /'slow-2g', '2g'/)
  assert.match(prefetch, /\[ '\/app', '\/admin' \]/)
  assert.match(prefetch, /currentIsAdmin !== targetIsAdmin/)
  assert.match(prefetch, /\[data-prefetch-safe="true"\]/)
  assert.match(prefetch, /if \(!knownAppPath\)/)
  assert.doesNotMatch(prefetch, /closest<HTMLElement>\('a\[href\]/)
})

test('stateful page visits acknowledge effects after mount and attachments never prefetch', () => {
  const receipt = readFileSync(
    new URL('../../app/javascript/lib/navigationReceipt.ts', import.meta.url),
    'utf8',
  )
  const attachmentList = readFileSync(
    new URL('../../app/javascript/components/portal/PostAttachmentsList.vue', import.meta.url),
    'utf8',
  )

  assert.match(receipt, /method: method\.toUpperCase\(\)/)
  assert.match(receipt, /X-Requested-With': 'XMLHttpRequest'/)
  assert.match(receipt, /receipt_token: receiptToken/)
  assert.match(attachmentList, /data-no-prefetch/)
  assert.match(attachmentList, /download/)
})
