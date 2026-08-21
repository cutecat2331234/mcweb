import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

const page = readFileSync(
  resolve(process.cwd(), 'app/javascript/pages/Account/Show.vue'),
  'utf8',
)
const routes = readFileSync(resolve(process.cwd(), 'app/javascript/lib/routes.ts'), 'utf8')
const staffLayout = readFileSync(resolve(process.cwd(), 'app/javascript/layouts/StaffLayout.vue'), 'utf8')

test('account center is a state dashboard built from the shared Arco UI library', () => {
  assert.match(page, /defineOptions\(\{ layout: PortalLayout \}\)/)
  assert.match(page, /from '@mcweb\/ui'/)
  assert.match(page, /<PageHeader/)
  assert.match(page, /<Descriptions/)
  assert.match(page, /<Statistic/)
  assert.match(page, /<List/)
  assert.match(page, /props\.identity/)
  assert.match(page, /security\.email_verified/)
  assert.match(page, /props\.activity/)
  assert.match(page, /props\.minecraft_enabled/)
  assert.match(page, /routes\.identityProfile/)
  assert.match(page, /routes\.securityPassword/)
  assert.match(page, /routes\.security/)
  assert.match(page, /routes\.minecraftLink/)
  assert.match(page, /routes\.forumNotifications/)
  assert.match(page, /routes\.forumMessages/)
  assert.match(page, /routes\.forumDrafts/)
  assert.match(page, /routes\.sessionsManagement/)
  assert.doesNotMatch(page, /components\/ui\//)
  assert.doesNotMatch(page, /hoverable/)
  assert.doesNotMatch(page, /gradient|translate[XY]?\(/i)
})

test('account and identity self-service routes are application-level destinations', () => {
  assert.match(routes, /account: `\$\{appPrefix\}\/account`/)
  assert.match(routes, /identityProfile: `\$\{appPrefix\}\/identity\/profile`/)
  assert.match(routes, /securityPassword: `\$\{appPrefix\}\/identity\/security\/password`/)
  assert.equal((staffLayout.match(/visit\(routes\.app\)/g) || []).length, 2)
  assert.doesNotMatch(staffLayout, /visit\(routes\.forum\)/)
})
