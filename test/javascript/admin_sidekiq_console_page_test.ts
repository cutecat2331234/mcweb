import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'
import {
  adminUrlFromSidekiqFrameUrl,
  isSidekiqAdminReturnUrl,
  normalizeSidekiqFrameUrl,
  normalizeSidekiqStandaloneUrl,
} from '../../app/javascript/lib/sidekiqNavigation.ts'

function source(relativePath: string) {
  return readFileSync(resolve(process.cwd(), relativePath), 'utf8')
}

test('admin owns a dedicated and same-origin Sidekiq console host', () => {
  const page = source('app/javascript/pages/Admin/System/Sidekiq/Index.vue')
  const routes = source('app/javascript/lib/adminRoutes.ts')
  const railsRoutes = source('config/routes.rb')
  const layout = source('app/javascript/layouts/ArcoAdminLayout.vue')
  const jobsPage = source('app/javascript/pages/Admin/System/Jobs/Index.vue')
  const controller = source('app/controllers/admin/system/sidekiq_controller.rb')

  assert.match(routes, /sidekiq: '\/admin\/system\/sidekiq'/)
  assert.match(routes, /sidekiqWeb: '\/jobs'/)
  assert.match(
    railsRoutes,
    /get "sidekiq\(\/\*sidekiq_path\)"[\s\S]*?format: false/,
  )
  assert.match(
    layout,
    /label: t\('admin\.sidekiq\.nav'\),\s+href: adminRoutes\.sidekiq,\s+permissionKey: 'system\.sidekiq\.read'/,
  )
  assert.match(controller, /require_permission\("system\.sidekiq\.read"\)/)
  assert.match(controller, /sidekiqUrl: frame_url/)
  assert.match(jobsPage, /includes\('system\.sidekiq\.read'\)/)
  assert.match(jobsPage, /<a-grid-item v-if="canAccessSidekiq">/)
  assert.match(jobsPage, /:href="adminRoutes\.sidekiq"/)
  assert.match(page, /<a-page-header/)
  assert.match(page, /<a-card/)
  assert.match(page, /<iframe/)
  assert.match(page, /:src="frameSrc"/)
  assert.match(page, /:href="standaloneUrl"/)
  assert.match(page, /target="_blank"/)
  assert.match(page, /rel="noopener noreferrer"/)
  assert.match(page, /data-admin-hard-navigation/)
  assert.match(page, /@load="handleFrameLoad"/)
  assert.match(page, /@error="handleFrameError"/)
  assert.match(page, /referrerpolicy="same-origin"/)
  assert.match(page, /mcweb-embedded-console/)
  assert.match(page, /contentDocument\?\.querySelector/)
  assert.match(page, /beforeunload/)
  assert.match(page, /router\.replace\(\{/)
  assert.match(page, /sidekiqUrl: normalizedFrameUrl/)
  assert.match(page, /@back="router\.visit\(adminRoutes\.dashboard\)"/)
  assert.match(page, /:aria-busy="!frameLoaded && !frameFailed"/)
  assert.match(page, /<a-card v-if="!frameFailed"/)
  assert.doesNotMatch(page, /\ssandbox(?:=|\s|>)/)
  assert.doesNotMatch(page, /route\.query|<style/)
})

test('Sidekiq deep links stay same-origin and keep only owned query fields', () => {
  const origin = 'https://mcweb.example'
  const frameUrl = normalizeSidekiqFrameUrl(
    '/jobs/retries?page=2&token=secret&substr=mailer',
    origin,
  )

  assert.equal(frameUrl, '/jobs/retries?page=2&substr=mailer')
  assert.equal(
    adminUrlFromSidekiqFrameUrl(frameUrl!, origin),
    '/admin/system/sidekiq/retries?page=2&substr=mailer',
  )
  assert.equal(normalizeSidekiqFrameUrl('/jobs', origin), '/jobs/')
  assert.equal(
    adminUrlFromSidekiqFrameUrl('/jobs/', origin),
    '/admin/system/sidekiq',
  )
  assert.equal(
    normalizeSidekiqFrameUrl('https://outside.example/jobs', origin),
    null,
  )
  assert.equal(normalizeSidekiqFrameUrl('/jobs/%2e%2e/admin', origin), null)
  assert.equal(normalizeSidekiqFrameUrl('/jobs/queues/%5Cescape', origin), null)
  assert.equal(
    normalizeSidekiqFrameUrl(`/jobs/queues/${encodeURIComponent('界'.repeat(200))}`, origin),
    null,
  )
  assert.equal(normalizeSidekiqFrameUrl('/jobs/stats', origin), null)
  assert.equal(normalizeSidekiqFrameUrl('/jobs/profiles/profile-key', origin), null)
  assert.equal(normalizeSidekiqFrameUrl('/jobs/profiles/profile-key/data', origin), null)
  assert.equal(
    normalizeSidekiqStandaloneUrl('/jobs/profiles/profile-key/data', origin),
    '/jobs/profiles/profile-key/data',
  )
  assert.equal(
    normalizeSidekiqFrameUrl('/jobs/cron/namespaces/default', origin),
    '/jobs/cron/namespaces/default',
  )
  assert.equal(
    normalizeSidekiqFrameUrl('/jobs/queues/default?count=0&page=01&direction=sideways', origin),
    '/jobs/queues/default?page=1',
  )
  assert.equal(
    normalizeSidekiqFrameUrl('/jobs/metrics/ExampleWorker?period=72h', origin),
    '/jobs/metrics/ExampleWorker?period=8h',
  )
  assert.equal(
    isSidekiqAdminReturnUrl('/admin/system/sidekiq', origin),
    true,
  )
  assert.equal(
    isSidekiqAdminReturnUrl('/admin/system/sidekiq?return=outside', origin),
    false,
  )
})

test('the shared Admin stylesheet owns adaptive embedded-console geometry', () => {
  const css = source('app/javascript/styles/arco-admin.css')

  assert.match(css, /\.mc-admin-embedded-tool__frame\s*\{[\s\S]*?width:\s*100%/)
  assert.match(css, /height:\s*clamp\(600px, calc\(100dvh - 236px\), 1080px\)/)
  assert.match(css, /border:\s*0/)
  assert.match(css, /visibility:\s*hidden/)
  assert.match(css, /\.mc-admin-embedded-tool__frame\.is-ready\s*\{[\s\S]*?visibility:\s*visible/)
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
