import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const navigation = readFileSync(
  new URL('../../app/javascript/lib/applicationNavigation.ts', import.meta.url),
  'utf8',
)
const factory = readFileSync(
  new URL('../../app/javascript/lib/createInertiaApplication.ts', import.meta.url),
  'utf8',
)
const prefetch = readFileSync(
  new URL('../../app/javascript/lib/intentPrefetch.ts', import.meta.url),
  'utf8',
)

test('same-application pages use Inertia and cross-application links use documents', () => {
  assert.match(navigation, /match\?\.application\?\.id === applicationId/)
  assert.match(navigation, /match\?\.rule\.kind === 'inertia_page'/)
  assert.match(navigation, /window\.location\.assign\(url\.href\)/)
  assert.match(navigation, /confirmUnsavedNavigation\(\)/)
})

test('delegated navigation does not double-dispatch component-owned links', () => {
  assert.match(navigation, /document\.addEventListener\('click', onDocumentClick, true\)/)
  assert.match(navigation, /document\.addEventListener\('click', onApplicationClick\)/)
  assert.match(navigation, /if \(event\.defaultPrevented/)
})

test('each application installs route-aware prefetch through the shared bootstrap', () => {
  assert.match(factory, /installIntentPrefetch\(\{ applicationId \}\)/)
  assert.match(prefetch, /resolveFrontendRoute/)
  assert.match(prefetch, /match\.rule\.kind !== 'inertia_page'/)
  assert.match(prefetch, /connection\.saveData/)
})

test('state-changing visits carry csrf, locale, and application identity', () => {
  assert.match(factory, /\.\.\.csrfHeaders\(\)/)
  assert.match(factory, /\.\.\.localeRequestHeaders\(\)/)
  assert.match(factory, /\.\.\.frontendApplicationRequestHeaders\(applicationId\)/)
  assert.match(factory, /claimSubmittedForm\(event\.detail\.visit\.id\)/)
})
