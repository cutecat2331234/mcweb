import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

const layout = readFileSync(
  resolve(process.cwd(), 'app/javascript/layouts/StaffLayout.vue'),
  'utf8',
)
const queue = readFileSync(
  resolve(process.cwd(), 'app/javascript/pages/Staff/ModerationCases/Index.vue'),
  'utf8',
)
const portalLayout = readFileSync(
  resolve(
    process.cwd(),
    'app/javascript/components/application-shell/ApplicationPortalShell.vue',
  ),
  'utf8',
)
const entrypoint = readFileSync(
  resolve(process.cwd(), 'app/javascript/entrypoints/staff.ts'),
  'utf8',
)
const shell = readFileSync(
  resolve(process.cwd(), 'app/javascript/shells/staff.ts'),
  'utf8',
)

test('staff workspace keeps an independent entry while reusing the application shell', () => {
  assert.match(layout, /import ApplicationPortalShell from '@\/components\/application-shell\/ApplicationPortalShell\.vue'/)
  assert.match(layout, /<ApplicationPortalShell>/)
  assert.doesNotMatch(layout, /AdminLayout/)
  assert.match(entrypoint, /applicationId:\s*'staff'/)
  assert.match(entrypoint, /providerComponent:\s*AppProvider/)
  assert.match(portalLayout, /window\.matchMedia\('\(max-width: 991px\)'\)/)
  assert.match(portalLayout, /<LayoutSider[\s\S]*?:width="256"/)
  assert.match(portalLayout, /class="mc-page-content mc-page-surface mc-portal-content"/)
  assert.match(portalLayout, /v-accessible-form-control-names/)
  assert.match(shell, /visibilityProp:\s*'auth\.user\.can_review_report_appeals'/)
  assert.doesNotMatch(layout, /<style\b/)
})

test('staff queue updates locally and uses centered modals for review actions', () => {
  assert.match(queue, /defineOptions\(\{ layout: StaffLayout \}\)/)
  assert.match(queue, /getJson<\{ case: ModerationCaseDetail \}>/)
  assert.match(queue, /postJson<\{ case: ModerationCase/)
  assert.match(queue, /function replaceCase/)
  assert.match(queue, /<Modal[\s\S]*align-center/)
  assert.match(queue, /<ModerationActionModal/)
  assert.doesNotMatch(queue, /<Drawer/)
  assert.doesNotMatch(queue, /(?:document|window)\.location\.reload/)
  assert.doesNotMatch(queue, /<style\b/)
})
