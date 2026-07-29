import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import test from 'node:test'

const root = process.cwd()
const read = (file: string) => fs.readFileSync(path.join(root, file), 'utf8')

test('audit index uses Arco filters, SPA pagination, and a download-only export', () => {
  const source = read('app/javascript/pages/Admin/AuditLogs/Index.vue')

  assert.match(source, /import AdminLayout from '@\/layouts\/AdminLayout\.vue'/)
  assert.match(source, /<DatePicker/)
  assert.match(source, /<Table/)
  assert.match(source, /<Pagination/)
  assert.match(source, /router\.get\(window\.location\.pathname/)
  assert.match(source, /anchor\.download = ''/)
  assert.doesNotMatch(source, /window\.location\.(assign|reload)/)
})

test('audit detail renders immutable state in responsive Arco cards', () => {
  const source = read('app/javascript/pages/Admin/AuditLogs/Show.vue')

  assert.match(source, /<Descriptions/)
  assert.match(source, /<Grid :cols="\{ xs: 1, lg: 2 \}"/)
  assert.match(source, /beforeState/)
  assert.match(source, /afterState/)
  assert.match(source, /metadata/)
  assert.doesNotMatch(source, /<form/)
})
