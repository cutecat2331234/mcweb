import assert from 'node:assert/strict'
import { existsSync, readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

import en from '../../app/javascript/locales/en.ts'
import zhCN from '../../app/javascript/locales/zh-CN.ts'

function source(path: string) {
  return readFileSync(resolve(process.cwd(), path), 'utf8')
}

const pagePath = 'app/javascript/pages/Account/Notifications/Index.vue'
const page = source(pagePath)
const layout = source('app/javascript/layouts/PortalLayout.vue')
const sharedProps = source('app/controllers/concerns/inertia_shared_props.rb')
const controller = source('app/controllers/account/notifications_controller.rb')

test('notification center belongs to the account route and keeps the existing interaction contract', () => {
  assert.equal(existsSync(resolve(process.cwd(), pagePath)), true)
  assert.equal(existsSync(resolve(process.cwd(), 'app/javascript/pages/Community/Notifications/Index.vue')), false)
  assert.match(page, /defineOptions\(\{ layout: PortalLayout \}\)/)
  assert.match(page, /routes\.accountNotifications/)
  assert.match(page, /notificationGroups/)
  assert.match(controller, /notificationGroups: grouped/)
  assert.match(page, /categoryFilters/)
  assert.match(page, /dismissAlertsUrl/)
  assert.match(page, /commitNavigationEffect/)
  assert.match(page, /deleteNotification/)
  assert.match(page, /markRead/)
  assert.match(page, /from '@mcweb\/ui'/)
  assert.match(page, /from '@\/lib\/arcoConfirm'/)
  assert.match(page, /<RadioGroup/)
  assert.match(page, /<Select/)
  assert.match(page, /<Tag/)
  assert.match(page, /<IconClose/)
  assert.match(page, /<Collapse/)
  assert.match(page, /<Card/)
  assert.match(page, /<List/)
  assert.match(page, /<Empty/)
  assert.match(page, /<Pagination/)
  assert.match(
    page,
    /const filterNavigationOptions = \{\s*preserveState: true,\s*preserveScroll: true,\s*replace: true,\s*\}/m,
  )
  for (const filterHandler of [
    'switchCategory',
    'switchRead',
    'switchPeriod',
    'switchType',
    'removeFilter',
    'clearAllFilters',
  ]) {
    assert.match(
      page,
      new RegExp(`function ${filterHandler}\\([\\s\\S]*?router\\.get\\([\\s\\S]*?filterNavigationOptions[\\s\\S]*?\\n}`),
      filterHandler,
    )
  }
  assert.doesNotMatch(page, /routes\.forumNotifications|\/forum\/notifications/)
  assert.doesNotMatch(controller, /^\s+notifications: grouped/m)
  assert.doesNotMatch(controller, /flat_notifications/)
  assert.doesNotMatch(page, /community\.notifications|breadcrumb\.forum/)
  assert.doesNotMatch(page, /accountNotifications\.subtitle|:subtitle=/)
  assert.doesNotMatch(page, /^\s+notifications:\s*NotificationGroup\[\]/m)
  assert.doesNotMatch(page, /@\/components\/ui\/(?:Button|Badge)\.vue/)
  assert.doesNotMatch(page, /from '@\/lib\/useConfirm'/)
  assert.doesNotMatch(page, /@\/components\/portal\/(?:Breadcrumb|PageHeader|Pagination)\.vue/)
  assert.doesNotMatch(page, /<button\b/)
  assert.doesNotMatch(page, /\bclosable\b/)
  assert.doesNotMatch(page, /focus-visible:|shadow(?:-|\b)|bg-gradient|translate-[xy]?-/)
  assert.doesNotMatch(page, /<style\b/)
})

test('portal notification entry is independent from the forum feature flag', () => {
  assert.match(layout, /v-if="auth\.user && notifications"/)
  assert.doesNotMatch(layout, /v-if="features\.forum && auth\.user && notifications"/)
  assert.match(layout, /@click="visit\(notifications\.url\)"/)
  assert.match(sharedProps, /logged_in\? && frontend_template_scope_for_request == "portal"/)
})

test('account notification copy is symmetric in English and Simplified Chinese', () => {
  const english = en.accountNotifications
  const chinese = zhCN.accountNotifications

  assert.deepEqual(Object.keys(english).sort(), Object.keys(chinese).sort())
  assert.equal(en.breadcrumb.account, 'Account')
  assert.equal(zhCN.breadcrumb.account, '账户')
  assert.equal('subtitle' in english, false)
  assert.equal('subtitle' in chinese, false)
})
