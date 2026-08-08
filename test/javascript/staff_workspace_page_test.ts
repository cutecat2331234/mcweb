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
  assert.match(layout, /marginLeft: isCompact \? '0' : '236px'/)
  assert.match(layout, /signOutConfirmTitle/)
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
