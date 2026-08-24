import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

function projectSource(relativePath: string) {
  return readFileSync(new URL(`../../${relativePath}`, import.meta.url), 'utf8')
}

test('Developer Workbench uses Arco for redacted diagnostics and audited tools', () => {
  const source = projectSource(
    'app/javascript/pages/Admin/System/DeveloperWorkbench/Show.vue',
  )

  assert.match(source, /<a-page-header/)
  assert.match(source, /<a-alert/)
  assert.match(source, /<a-card/)
  assert.match(source, /<a-descriptions/)
  assert.match(source, /<a-grid/)
  assert.match(source, /<a-table/)
  assert.match(source, /<a-statistic/)
  assert.match(source, /<a-empty/)
  assert.match(source, /<a-drawer/)
  assert.match(source, /<a-select/)
  assert.match(source, /<a-form/)
  assert.match(source, /router\.visit/)
  assert.match(source, /router\.post/)
  assert.match(source, /preserveScroll:\s*true/)
  assert.match(source, /navigator\.clipboard\.writeText/)
  assert.doesNotMatch(source, /<(?:input|select|button|table|form)(?:\s|>)/)
  assert.doesNotMatch(source, /<style(?:\s|>)/)
  assert.doesNotMatch(source, /window\.location/)
})

test('Developer Workbench navigation is gated by the server-provided RBAC flag', () => {
  const layout = projectSource('app/javascript/layouts/ArcoAdminLayout.vue')
  const routes = projectSource('app/javascript/lib/adminRoutes.ts')

  assert.match(layout, /developerMode\.value\.workbench_access/)
  assert.match(layout, /adminRoutes\.developerWorkbench/)
  assert.match(routes, /developerWorkbench:\s*'\/admin\/system\/developer-workbench'/)
})

test('Developer Workbench copy is available in English and Chinese', () => {
  const english = projectSource('app/javascript/locales/en.ts')
  const chinese = projectSource('app/javascript/locales/zh-CN.ts')

  for (const source of [english, chinese]) {
    assert.match(source, /developerWorkbench:\s*\{/)
    assert.match(source, /productionWarningTitle:/)
    assert.match(source, /readOnlyDescription:/)
    assert.match(source, /activeConfiguration:/)
    assert.match(source, /privacyDescription:/)
    assert.match(source, /seedOptions:\s*\{/)
    assert.match(source, /attachmentOptions:\s*\{/)
    assert.match(source, /copySuccess:/)
    assert.match(source, /taskTypes:\s*\{/)
  }
})

test('Developer Mode global tools keep the persistent warning in each layout', () => {
  const adminTools = projectSource(
    'app/javascript/components/admin/DeveloperModeTools.vue',
  )
  const portalTools = projectSource(
    'app/javascript/components/portal/DeveloperModeTools.vue',
  )
  const adminLayout = projectSource(
    'app/javascript/layouts/ArcoAdminLayout.vue',
  )
  const portalLayout = projectSource(
    'app/javascript/layouts/PortalLayout.vue',
  )
  const websiteLayout = projectSource(
    'app/javascript/layouts/WebsiteLayout.vue',
  )

  assert.match(adminTools, /<a-drawer/)
  assert.match(adminTools, /navigator\.clipboard\.writeText/)
  assert.match(adminTools, /persona_switch_url/)
  assert.match(adminTools, /performSharedAction/)
  assert.match(adminTools, /navigateFrontendDocument/)
  assert.match(adminTools, /<a-watermark/)
  assert.match(adminTools, /<a-back-top/)
  assert.match(adminTools, /common\.developerModeBadge/)
  assert.doesNotMatch(adminTools, /\s(?:v-bind:class|:class|class)=/)
  assert.doesNotMatch(adminTools, /<style\b/)
  assert.match(portalTools, /persona_switch_url/)
  assert.match(portalTools, /performSharedAction/)
  assert.match(portalTools, /navigateFrontendDocument/)
  assert.match(portalTools, /<a-watermark/)
  assert.match(portalTools, /<a-back-top/)
  assert.match(portalTools, /<a-drawer/)
  assert.match(portalTools, /<a-button/)
  assert.match(portalTools, /common\.developerModeBadge/)
  assert.doesNotMatch(portalTools, /<button\b/)
  assert.doesNotMatch(portalTools, /<style\b/)

  for (const tools of [adminTools, portalTools]) {
    const drawerStart = tools.indexOf('<a-drawer')
    assert.ok(drawerStart > 0, 'developer tools must keep secondary details in a drawer')
    assert.doesNotMatch(
      tools.slice(0, drawerStart),
      /<a-alert/,
      'developer tools must not duplicate the layout warning while the drawer is closed',
    )
    assert.match(tools.slice(drawerStart), /<a-alert/)
  }

  for (const source of [adminLayout, portalLayout, websiteLayout]) {
    assert.match(source, /<DeveloperModeTools/)
    assert.equal(
      source.match(/data-testid="developer-mode-banner"/g)?.length,
      1,
      'each layout must render exactly one persistent developer mode warning',
    )
  }
})

test('fake payment page exposes explicit development outcomes without hard reloads', () => {
  const source = projectSource(
    'app/javascript/pages/Payments/Fake/Show.vue',
  )

  assert.match(source, /developerScenarios/)
  assert.match(source, /'success', 'failure', 'cancellation', 'delayed'/)
  assert.match(source, /form\.post\(payUrl/)
  assert.match(source, /preserveScroll:\s*true/)
  assert.doesNotMatch(source, /window\.location|location\.reload/)
})
