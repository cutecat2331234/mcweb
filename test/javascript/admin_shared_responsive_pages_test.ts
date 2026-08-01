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
  assert.match(source, /router\.visit\(url, \{ preserveScroll: true \}\)/)
  assert.match(source, /@click="visit\(subscription\.editUrl\)"/)
  assert.doesNotMatch(source, /:href="(?:subscription\.editUrl|record\.editUrl|newUrl)"/)
  assert.doesNotMatch(source, /<style\b/)
  assertNoHardReload(source)
})

test('dashboard relies on Arco responsive primitives with one bounded semantic style block', () => {
  const source = pageSource('Dashboard/Index.vue')

  assert.match(source, /<a-grid\b/)
  assert.match(source, /:cols="\{ xs: 1, sm: 2, lg: 3, xl: 4 \}"/)
  assert.match(source, /:span="metricSpan\(index\)"/)
  assert.match(source, /<a-statistic\b/)
  assert.match(source, /<a-typography-title\b/)
  assert.match(source, /:body-style="\{ minWidth: 0 \}"/)
  assert.match(source, /:scroll="\{ x: 720 \}"/)
  assert.equal((source.match(/<style\b/g) ?? []).length, 1)
  assert.match(source, /\.admin-dashboard :deep\(\.arco-card-body\)/)
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
