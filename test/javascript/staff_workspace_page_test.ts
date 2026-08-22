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

test('staff workspace is independent from the administrator shell and responsive', () => {
  assert.match(layout, /from '@mcweb\/ui'/)
  assert.doesNotMatch(layout, /AdminLayout/)
  assert.match(layout, /window\.matchMedia\('\(max-width: 991px\)'\)/)
  assert.match(layout, /marginLeft: isCompact \? '0' : 'var\(--mc-shell-sidebar-width, 248px\)'/)
  assert.match(layout, /width: isCompact \? '100%' : 'calc\(100% - var\(--mc-shell-sidebar-width, 248px\)\)'/)
  assert.match(layout, /class="mc-page-content mc-page-surface"/)
  assert.match(layout, /class="mc-page-container"/)
  assert.match(layout, /boxSizing: 'border-box'/)
  assert.match(layout, /background: 'var\(--color-bg-1\)'/)
  assert.match(layout, /import AdminLanguageSwitcher from '@\/components\/admin\/AdminLanguageSwitcher\.vue'/)
  assert.match(layout, /<AdminLanguageSwitcher \/>/)
  assert.match(layout, /signOutConfirmTitle/)
  assert.match(layout, /safeSignOut/)
  assert.match(layout, /onFinish: \(\) =>/)
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
