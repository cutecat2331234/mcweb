import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

function source(relativePath: string) {
  return readFileSync(resolve(process.cwd(), relativePath), 'utf8')
}

test('admin owns a fixed same-origin Sidekiq console host', () => {
  const page = source('app/javascript/pages/Admin/System/Sidekiq/Index.vue')
  const routes = source('app/javascript/lib/adminRoutes.ts')
  const layout = source('app/javascript/layouts/ArcoAdminLayout.vue')
  const controller = source('app/controllers/admin/system/sidekiq_controller.rb')

  assert.match(routes, /sidekiq: '\/admin\/system\/sidekiq'/)
  assert.match(routes, /sidekiqWeb: '\/jobs'/)
  assert.match(
    layout,
    /label: t\('admin\.sidekiq\.nav'\),\s+href: adminRoutes\.sidekiq,\s+permissionKey: 'system\.jobs\.read'/,
  )
  assert.match(controller, /require_permission\("system\.jobs\.read"\)/)
  assert.match(controller, /Admin\/System\/Sidekiq\/Index/)
  assert.match(page, /<a-page-header/)
  assert.match(page, /<a-card/)
  assert.match(page, /<iframe/)
  assert.match(page, /:src="adminRoutes\.sidekiqWeb"/)
  assert.match(page, /target="_blank"/)
  assert.match(page, /data-admin-hard-navigation/)
  assert.match(page, /@load="handleFrameLoad"/)
  assert.match(page, /@error="handleFrameError"/)
  assert.doesNotMatch(page, /\ssandbox(?:=|\s|>)/)
  assert.doesNotMatch(page, /defineProps|URLSearchParams|route\.query|<style/)
})

test('the shared Admin stylesheet owns adaptive embedded-console geometry', () => {
  const css = source('app/javascript/styles/arco-admin.css')

  assert.match(css, /\.mc-admin-embedded-tool__frame\s*\{[\s\S]*?width:\s*100%/)
  assert.match(css, /height:\s*clamp\(600px, calc\(100dvh - 236px\), 1080px\)/)
  assert.match(css, /border:\s*0/)
  assert.doesNotMatch(css, /\.mc-admin-embedded-tool[^}]*transform:/)
})

test('both Admin locale bundles own the Sidekiq host copy', () => {
  for (const locale of [
    source('app/javascript/locales/en.ts'),
    source('app/javascript/locales/zh-CN.ts'),
  ]) {
    assert.match(locale, /sidekiq:\s*\{/)
    assert.match(locale, /openStandalone:/)
    assert.match(locale, /loadFailedTitle:/)
    assert.match(locale, /frameTitle:/)
  }
})
