import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import test from 'node:test'

const source = fs.readFileSync(
  path.join(process.cwd(), 'app/javascript/pages/Admin/Store/Finance/Index.vue'),
  'utf8',
)
const layout = fs.readFileSync(
  path.join(process.cwd(), 'app/javascript/layouts/ArcoAdminLayout.vue'),
  'utf8',
)
const routes = fs.readFileSync(
  path.join(process.cwd(), 'app/javascript/lib/adminRoutes.ts'),
  'utf8',
)

test('finance workbench uses Arco hierarchy, responsive documents, drawer timeline, and progress', () => {
  for (const component of [
    'PageHeader',
    'Alert',
    'Statistic',
    'Table',
    'Card',
    'Drawer',
    'Timeline',
    'Progress',
    'Pagination',
  ]) {
    assert.match(source, new RegExp(`<${component}`))
  }
  assert.match(source, /:span="\{ xs: 0, md: 24 \}"/)
  assert.match(source, /:span="\{ xs: 24, md: 0 \}"/)
  assert.match(source, /<Grid :cols="1" :row-gap="12"/)
  assert.match(source, /:cols="\{ xs: 1, md: 2, xl: 3 \}"/)
  assert.doesNotMatch(
    source,
    /\s(?:class|:class|v-bind:class|style|:style|v-bind:style)=|<style\b|<(?:form|label|input|select|textarea)(?:\s|>)/,
  )
  assert.doesNotMatch(source, /<Form[^>]*@submit\.prevent/)
})

test('finance filters and asynchronous export update only local Inertia props', () => {
  assert.match(source, /tax_rate_bps/)
  assert.match(source, /tax_country/)
  assert.match(source, /tax_region/)
  assert.match(source, /requestExport/)
  assert.match(source, /setInterval\(pollExports, 5_000\)/)
  assert.match(source, /only: \['exports'\]/)
  assert.match(source, /only: \['documents', 'summary'\]/)
  assert.doesNotMatch(source, /window\.location|location\.reload/)
})

test('finance navigation is gated by its read permission and has canonical admin routes', () => {
  assert.match(layout, /permissionKey: 'store\.finance\.read'/)
  assert.match(layout, /href: adminRoutes\.storeFinance/)
  assert.match(routes, /storeFinance: '\/admin\/store\/finance'/)
  assert.match(routes, /storeFinanceExportDownload/)
})

test('document transitions retain reason and idempotent request context', () => {
  assert.match(source, /transition_action/)
  assert.match(source, /transitionReason/)
  assert.match(source, /crypto\.randomUUID\(\)/)
  assert.match(source, /immutableDescription/)
})
