import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

const helper = readFileSync(
  resolve(process.cwd(), 'app/javascript/lib/safeSignOut.ts'),
  'utf8',
)
const authenticatedHistory = readFileSync(
  resolve(process.cwd(), 'app/javascript/lib/authenticatedHistory.ts'),
  'utf8',
)
const applicationFactory = readFileSync(
  resolve(process.cwd(), 'app/javascript/lib/createInertiaApplication.ts'),
  'utf8',
)
const portalLayout = readFileSync(
  resolve(
    process.cwd(),
    'app/javascript/components/application-shell/ApplicationPortalShell.vue',
  ),
  'utf8',
)
const staffLayout = readFileSync(
  resolve(process.cwd(), 'app/javascript/layouts/StaffLayout.vue'),
  'utf8',
)

test('sign out uses the registered shared action and always reaches a safe public document', () => {
  assert.match(helper, /performSharedAction\(documentFrontendApplicationId\(\), routes\.signOut/)
  assert.match(helper, /method: 'DELETE'/)
  assert.match(helper, /error instanceof SharedActionError && error\.recoveryStarted/)
  assert.match(helper, /navigateFrontendDocument\(routes\.signedOut\)/)
  assert.match(helper, /window\.location\.assign\(routes\.signedOut\)/)
  assert.match(helper, /invalidateAuthenticatedHistory\(\)/)
  assert.match(helper, /hooks\.onStart\?\.\(\)/)
  assert.match(helper, /hooks\.onFinish\?\.\(\)/)
  assert.match(helper, /finally \{\s*finish\(\)/)
})

test('sign out invalidates encrypted history and restored authenticated documents', () => {
  assert.match(authenticatedHistory, /\['historyKey', 'historyIv'\]/)
  assert.match(authenticatedHistory, /browserStorage\('sessionStorage'\)/)
  assert.match(authenticatedHistory, /browserStorage\('localStorage'\)/)
  assert.match(authenticatedHistory, /window\.history\.replaceState/)
  assert.match(authenticatedHistory, /window\.addEventListener\('storage'/)
  assert.match(authenticatedHistory, /window\.addEventListener\('pageshow'/)
  assert.match(authenticatedHistory, /window\.location\.replace\(destination\.href\)/)
  assert.match(authenticatedHistory, /SESSION_ARMED_KEY/)
  assert.match(authenticatedHistory, /invalidatePreviouslyAuthenticatedHistory/)
  assert.match(applicationFactory, /syncAuthenticatedHistoryBoundary\(domPage\)/)
  assert.match(applicationFactory, /syncAuthenticatedHistoryBoundary\(detail\.page\)/)
  assert.match(applicationFactory, /document\.addEventListener\('inertia:location'/)
  assert.match(applicationFactory, /url\.pathname === signedOut\.pathname/)
})

test('portal and staff callers use the shared loading-safe sign-out contract', () => {
  assert.match(portalLayout, /safeSignOut/)
  assert.match(portalLayout, /if \(signingOut\.value\) return/)
  assert.match(portalLayout, /:disabled="signingOut"/)
  assert.match(portalLayout, /onFinish:/)

  assert.match(staffLayout, /import ApplicationPortalShell from '@\/components\/application-shell\/ApplicationPortalShell\.vue'/)
  assert.match(staffLayout, /<ApplicationPortalShell>/)
})
