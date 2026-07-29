import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

const page = readFileSync(
  resolve(process.cwd(), 'app/javascript/pages/Admin/System/DataGovernance/Index.vue'),
  'utf8',
)
const layout = readFileSync(
  resolve(process.cwd(), 'app/javascript/layouts/ArcoAdminLayout.vue'),
  'utf8',
)
const routes = readFileSync(
  resolve(process.cwd(), 'app/javascript/lib/adminRoutes.ts'),
  'utf8',
)

test('data governance is an Arco table, drawer, and modal workbench without long collapse panels', () => {
  assert.match(page, /from '@mcweb\/ui'/)
  assert.match(page, /import AdminLayout from '@\/layouts\/AdminLayout\.vue'/)
  assert.match(page, /<Table/)
  assert.match(page, /<Drawer/)
  assert.match(page, /<Modal/)
  assert.match(page, /<Tabs/)
  assert.doesNotMatch(page, /<Collapse|<CollapseItem/)
  assert.doesNotMatch(page, /window\.location|document\.location/)
})

test('policy, hold, reversible deletion, restore, and permanent purge use in-app JSON requests', () => {
  assert.match(page, /savePolicy/)
  assert.match(page, /createHold/)
  assert.match(page, /releaseHold/)
  assert.match(page, /softDelete/)
  assert.match(page, /executeLifecycleAction/)
  assert.match(page, /method: action === 'restore' \? 'PATCH' : 'DELETE'/)
  assert.match(page, /router\.reload\(\{[\s\S]*preserveState: true/)
})

test('all product copy is namespaced and the permission-aware navigation exposes the workbench', () => {
  assert.match(page, /admin\.dataGovernance\./)
  assert.match(page, /resourceTypeLabel\(record\.targetType\)/)
  assert.doesNotMatch(page, />\s*(?:永久清理|软删除|设置保全|恢复|取消|保存)\s*</)
  assert.match(routes, /dataGovernance: '\/admin\/system\/data-governance'/)
  assert.match(layout, /permissionKey: 'data_governance\.read'/)
  assert.match(layout, /admin\.dataGovernance\.nav/)
})
