import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import test from 'node:test'

const projectRoot = path.resolve(import.meta.dirname, '..', '..')

function pageSource(relativePath: string) {
  return fs.readFileSync(
    path.join(projectRoot, 'app', 'javascript', 'pages', 'Admin', relativePath),
    'utf8',
  )
}

function javascriptSource(relativePath: string) {
  return fs.readFileSync(path.join(projectRoot, 'app', 'javascript', relativePath), 'utf8')
}

function assertNoHardReload(source: string) {
  assert.doesNotMatch(source, /\b(?:window\.)?location\.(?:reload|replace|assign)\s*\(/)
  assert.doesNotMatch(source, /\bwindow\.location\s*=/)
}

test('API keys use Arco responsive cards on narrow screens and a bounded table on desktop', () => {
  const source = pageSource('System/ApiKeys/Index.vue')

  assert.match(source, /<a-grid\b/)
  assert.match(source, /<a-grid-item\b/)
  assert.match(source, /:span="\{ xs: 24, sm: 12, md: 0 \}"/)
  assert.match(source, /:span="\{ xs: 0, md: 24 \}"/)
  assert.match(source, /<a-descriptions\b/)
  assert.match(source, /:scroll="\{ minWidth: 1080 \}"/)
  assert.match(source, /router\.post\(key\.revokeUrl\)/)
  assert.doesNotMatch(source, /<style\b/)
  assertNoHardReload(source)
})

test('webhook subscriptions use Arco responsive cards and preserve SPA edit navigation', () => {
  const source = pageSource('System/WebhookSubscriptions/Index.vue')

  assert.match(source, /<a-grid\b/)
  assert.match(source, /<a-grid-item\b/)
  assert.match(source, /:span="\{ xs: 24, sm: 12, md: 0 \}"/)
  assert.match(source, /:span="\{ xs: 0, md: 24 \}"/)
  assert.match(source, /<a-descriptions\b/)
  assert.match(source, /:scroll="\{ minWidth: 1120 \}"/)
  assert.match(source, /:href="subscription\.editUrl"/)
  assert.doesNotMatch(source, /<style\b/)
  assertNoHardReload(source)
})

test('dashboard relies on Arco responsive primitives without page-scoped CSS', () => {
  const source = pageSource('Dashboard/Index.vue')

  assert.match(source, /<a-row\b/)
  assert.match(source, /:xs="24"/)
  assert.match(source, /:sm="12"/)
  assert.match(source, /<a-statistic\b/)
  assert.match(source, /<a-typography-title\b/)
  assert.match(source, /:body-style="\{ minWidth: 0 \}"/)
  assert.match(source, /:scroll="\{ minWidth: 640 \}"/)
  assert.doesNotMatch(source, /<style\b/)
  assertNoHardReload(source)
})

test('admin entry registers Arco directly without leaking portal styles into the admin bundle', () => {
  const source = javascriptSource('entrypoints/admin.ts')

  assert.match(source, /import ArcoVue from '@arco-design\/web-vue'/)
  assert.match(source, /import '@arco-design\/web-vue\/dist\/arco\.css'/)
  assert.match(source, /import '@\/styles\/arco-admin\.css'/)
  assert.doesNotMatch(source, /@mcweb\/ui/)
  assert.doesNotMatch(source, /portal\.css/)
  assert.match(source, /\.use\(ArcoVue\)/)
})
