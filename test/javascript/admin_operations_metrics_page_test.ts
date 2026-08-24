import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

const source = readFileSync(
  resolve(process.cwd(), 'app/javascript/pages/Admin/System/Jobs/Index.vue'),
  'utf8',
)

test('operations trends use Arco statistics, progress, table, and range controls', () => {
  assert.match(source, /<a-radio-group/)
  assert.match(source, /<a-statistic/)
  assert.match(source, /<a-progress/)
  assert.match(source, /<a-table/)
  assert.match(source, /<a-empty/)
  assert.match(source, /<a-descriptions/)
  assert.match(source, /layout="vertical"/)
  assert.match(source, /<a-grid[\s\S]*?v-if="manualTasks\.length > 0"[\s\S]*?:cols="\{\s*xs:\s*1,\s*md:\s*2\s*\}"/)
  assert.doesNotMatch(source, /\s(?:class|:class|style|:style)=/)
  assert.doesNotMatch(source, /<(?:input|select|button|table|form|textarea)(?:\s|>)/)
  assert.doesNotMatch(source, /<style(?:\s|>)/)
  assert.doesNotMatch(source, /rounded-2xl|!rounded-none/)
})

test('range changes request only the metrics prop without remounting the page', () => {
  assert.match(source, /router\.get\(/)
  assert.match(source, /only: \['operationsMetrics'\]/)
  assert.match(source, /preserveState: true/)
  assert.match(source, /preserveScroll: true/)
  assert.doesNotMatch(source, /window\.location\.(?:reload|assign)/)
})

test('operations UI uses translated labels instead of implementation notes', () => {
  assert.match(source, /admin\.jobsPage\.metrics/)
  assert.doesNotMatch(source, />\s*(?:Metrics|Threshold|Query budget)\s*</)
  assert.doesNotMatch(source, /<(?:(?:input|select|button|table))(?:\s|>)/)
})
