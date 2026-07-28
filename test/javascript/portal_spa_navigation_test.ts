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
