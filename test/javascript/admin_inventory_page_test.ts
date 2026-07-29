import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import test from 'node:test'

const source = fs.readFileSync(
  path.join(process.cwd(), 'app/javascript/pages/Admin/Store/Inventory/Index.vue'),
  'utf8',
)

test('inventory operations use Arco surfaces and partial state refresh', () => {
  for (const component of ['PageHeader', 'Statistic', 'Table', 'Drawer', 'Modal', 'Timeline', 'Alert']) {
    assert.match(source, new RegExp(`<${component}`))
  }
  assert.match(source, /postJson<Authorization>/)
  assert.match(source, /router\.reload\(\{/)
  assert.match(source, /only: \['summary', 'targets'/)
  assert.doesNotMatch(source, /window\.location|location\.reload/)
})

test('inventory adjustment requires preview, reason and typed signed confirmation', () => {
  assert.match(source, /authorizeAdjustment/)
  assert.match(source, /authorization_token/)
  assert.match(source, /adjustment\.reason/)
  assert.match(source, /adjustment\.confirmation/)
  assert.match(source, /confirmationLabel/)
})
