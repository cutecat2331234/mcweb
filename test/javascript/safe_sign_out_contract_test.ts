import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

const helper = readFileSync(
  resolve(process.cwd(), 'app/javascript/lib/safeSignOut.ts'),
  'utf8',
)
const portalMenu = readFileSync(
  resolve(process.cwd(), 'app/javascript/components/portal/PortalUserMenu.vue'),
  'utf8',
)

test('sign out owns every Inertia terminal path and falls back to a full document visit', () => {
  assert.match(helper, /onSuccess: visitSafePublicPage/)
  assert.match(helper, /onError: visitSafePublicPage/)
  assert.match(helper, /onCancel: visitSafePublicPage/)
  assert.match(helper, /onHttpException: visitSafePublicPage/)
  assert.match(helper, /onNetworkError: visitSafePublicPage/)
  assert.match(helper, /onFinish: finish/)
  assert.match(helper, /window\.location\.assign\(routes\.signedOut\)/)
  assert.match(helper, /catch \{\s*visitSafePublicPage\(\)/)
})

test('portal and staff callers use the shared loading-safe sign-out contract', () => {
  assert.match(portalMenu, /safeSignOut/)
  assert.match(portalMenu, /:disabled="signingOut"/)
  assert.match(portalMenu, /:aria-busy="signingOut"/)
})
