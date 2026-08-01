import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import test from 'node:test'

const root = process.cwd()
const read = (file: string) => fs.readFileSync(path.join(root, file), 'utf8')

test('audit index uses direct Arco filters, SPA navigation, and a download-only export', () => {
  const source = read('app/javascript/pages/Admin/AuditLogs/Index.vue')

  assert.match(source, /import AdminLayout from '@\/layouts\/AdminLayout\.vue'/)
  assert.match(source, /defineOptions\(\{ layout: AdminLayout \}\)/)
  assert.match(source, /<a-date-picker/)
  assert.match(source, /<a-table/)
  assert.match(source, /<a-pagination/)
  assert.match(source, /<a-grid :cols="\{ xs: 1, md: 2, xl: 4 \}"/)
  assert.match(source, /router\.get\(window\.location\.pathname/)
  assert.match(source, /router\.visit\(url/)
  assert.doesNotMatch(source, /from '@mcweb\/ui'/)
  assert.doesNotMatch(source, /<style\b/)
  assert.match(source, /anchor\.download = ''/)
  assert.doesNotMatch(source, /window\.location\.(assign|reload)/)
})

test('audit detail renders immutable state in responsive Arco cards', () => {
  const source = read('app/javascript/pages/Admin/AuditLogs/Show.vue')

  assert.match(source, /import AdminLayout from '@\/layouts\/AdminLayout\.vue'/)
  assert.match(source, /defineOptions\(\{ layout: AdminLayout \}\)/)
  assert.match(source, /<a-descriptions/)
  assert.match(source, /<a-grid :cols="\{ xs: 1, lg: 2 \}"/)
  assert.match(source, /beforeState/)
  assert.match(source, /afterState/)
  assert.match(source, /metadata/)
  assert.doesNotMatch(source, /from '@mcweb\/ui'/)
  assert.doesNotMatch(source, /\s(?:v-bind:class|:class|class)=/)
  assert.doesNotMatch(source, /<style\b/)
  assert.doesNotMatch(source, /window\.location\.(?:assign|reload)/)
  assert.doesNotMatch(source, /<form/)
})
