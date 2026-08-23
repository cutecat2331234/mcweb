import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

const root = process.cwd()

function source(path: string): string {
  return readFileSync(resolve(root, path), 'utf8')
}

const layoutPaths = [
  'app/javascript/layouts/PortalLayout.vue',
  'app/javascript/layouts/ArcoAdminLayout.vue',
  'app/javascript/layouts/WebsiteLayout.vue',
]

test('all CE shells expose a persistent developer mode warning', () => {
  for (const path of layoutPaths) {
    const layout = source(path)

    assert.match(layout, /page\.props\.developer_mode/)
    assert.match(layout, /v-if="developerMode\.enabled"/)
    assert.match(layout, /data-testid="developer-mode-banner"/)
    assert.match(layout, /role="alert"/)
    assert.match(layout, /t\('common\.developerMode'\)/)
    assert.match(layout, /t\('common\.developerModeWarning'\)/)
    assert.match(layout, /developerMode(?:\.value)?\.production_environment/)
    assert.match(layout, /t\('common\.developerModeProductionWarning'\)/)
  }
})

test('each CE shell keeps its existing visual component system', () => {
  const portal = source(layoutPaths[0])
  const admin = source(layoutPaths[1])
  const website = source(layoutPaths[2])
  const websiteCss = source('app/javascript/styles/website.css')

  assert.match(portal, /<TriangleAlert/)
  assert.match(portal, /bg-amber-500\/10/)
  assert.match(admin, /<a-alert/)
  assert.match(admin, /class="arco-admin-developer-alert"/)
  assert.match(website, /class="website-developer-mode"/)
  assert.match(websiteCss, /\.website-developer-mode\s*\{/)
})

test('PortalLayout does not key its page content by the URL', () => {
  const portal = source(layoutPaths[0])

  assert.doesNotMatch(portal, /:key=["']page\.url["']/)
  assert.doesNotMatch(portal, /key\s*=\s*["'][^"']*page\.url/)
  assert.match(portal, /<div class="min-h-\[1px\]">\s*<slot\s*\/>/)
})

test('developer mode warnings are translated in English and Chinese', () => {
  const en = source('app/javascript/locales/en.ts')
  const zhCN = source('app/javascript/locales/zh-CN.ts')

  for (const locale of [en, zhCN]) {
    assert.match(locale, /developerMode:/)
    assert.match(locale, /developerModeWarning:/)
    assert.match(locale, /developerModeProductionWarning:/)
  }
})

test('Inertia documents expose noindex and retain the DEV title prefix', () => {
  for (const path of [
    'app/views/layouts/inertia.html.erb',
    'app/views/layouts/inertia_admin.html.erb',
  ]) {
    const layout = source(path)
    assert.match(layout, /data-developer-mode=/)
    assert.match(layout, /Mcweb::DeveloperMode\.enabled\?/)
    assert.match(layout, /name="robots" content="noindex, nofollow"/)
    assert.match(layout, /\[DEV\]/)
  }

  for (const path of [
    'app/javascript/lib/createInertiaApplication.ts',
  ]) {
    const entrypoint = source(path)
    assert.match(entrypoint, /dataset\.developerMode === 'true'/)
    assert.match(entrypoint, /dataset\.developerMode === 'true'/)
  }
})

test('legacy documents also expose the developer warning and noindex state', () => {
  for (const path of [
    'app/views/layouts/application.html.erb',
    'app/views/layouts/admin.html.erb',
    'app/views/layouts/website.html.erb',
    'app/views/layouts/setup.html.erb',
  ]) {
    const layout = source(path)
    assert.match(layout, /data-developer-mode=/)
    assert.match(layout, /name="robots" content="noindex, nofollow"/)
    assert.match(layout, /render "shared\/developer_mode_banner"/)
    assert.match(layout, /\[DEV\]/)
  }

  const banner = source('app/views/shared/_developer_mode_banner.html.erb')
  assert.match(banner, /role="alert"/)
  assert.match(banner, /mcweb\.developer_mode\.warning/)
  assert.match(banner, /Rails\.env\.production\?/)
})
