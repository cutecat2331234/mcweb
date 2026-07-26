import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

function projectSource(relativePath: string) {
  return readFileSync(new URL(`../../${relativePath}`, import.meta.url), 'utf8')
}

test('Developer Workbench is an Arco-only read-only Inertia page', () => {
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
  assert.match(source, /router\.visit/)
  assert.doesNotMatch(source, /useForm|router\.(?:post|patch|put|delete)/)
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
    assert.match(source, /taskTypes:\s*\{/)
  }
})
