import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import test from 'node:test'

const source = fs.readFileSync(
  path.join(process.cwd(), 'app/javascript/pages/Admin/Users/Permissions.vue'),
  'utf8',
)

test('permission explanation is an Arco member-view table with a bounded drawer', () => {
  assert.match(source, /import AdminLayout from '@\/layouts\/AdminLayout\.vue'/)
  assert.match(source, /<Table/)
  assert.match(source, /<Drawer/)
  assert.match(source, /calc\(100vw - 32px\)/)
  assert.match(source, /memberViewNotice/)
  assert.match(source, /record\.sources/)
  assert.doesNotMatch(source, /\{\{\s*(?:record|selected)\.key\s*\}\}/)
})

test('permission decisions are filtered locally without duplicating authorization logic', () => {
  assert.match(source, /const filteredRows = computed/)
  assert.match(source, /row\.allowed/)
  assert.doesNotMatch(source, /permission\?\(|effectivePermission|role_ids/)
})
