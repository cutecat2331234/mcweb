import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

const helper = readFileSync(
  resolve(process.cwd(), 'app/javascript/lib/safeSignOut.ts'),
  'utf8',
)
const portalLayout = readFileSync(
  resolve(process.cwd(), 'app/javascript/layouts/PortalLayout.vue'),
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
  assert.match(helper, /hooks\.onStart\?\.\(\)/)
  assert.match(helper, /hooks\.onFinish\?\.\(\)/)
  assert.match(helper, /finally \{\s*finish\(\)/)
})

test('portal and staff callers use the shared loading-safe sign-out contract', () => {
  assert.match(portalLayout, /safeSignOut/)
  assert.match(portalLayout, /if \(signingOut\.value\) return/)
  assert.match(portalLayout, /:disabled="signingOut"/)
  assert.match(portalLayout, /onFinish:/)

  assert.match(staffLayout, /safeSignOut/)
  assert.match(staffLayout, /if \(signingOut\.value\) return false/)
  assert.match(staffLayout, /:ok-loading="signingOut"/)
  assert.match(staffLayout, /onStart:/)
  assert.match(staffLayout, /onFinish:/)
})
