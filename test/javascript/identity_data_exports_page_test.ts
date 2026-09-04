import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const source = readFileSync(
  new URL('../../app/javascript/pages/Identity/DataExports/Index.vue', import.meta.url),
  'utf8',
)

test('identity data exports page uses partial Inertia actions for request, retry, and revoke', () => {
  assert.match(source, /router\.post\(/)
  assert.match(source, /router\.delete\(/)
  assert.match(source, /preserveScroll: true/)
  assert.doesNotMatch(source, /window\.location\.reload/)
})

test('identity data exports page shows explicit lifecycle and privacy states', () => {
  assert.match(source, /identity\.dataExports\.privacyTitle/)
  assert.match(source, /identity\.dataExports\.status\./)
  assert.match(source, /item\.downloadable/)
  assert.match(source, /item\.error_code/)
  assert.match(source, /item\.retryable/)
  assert.match(source, /data_export_size_exceeded/)
  assert.match(source, /data_export_resource_exhausted/)
})

test('identity data exports page renders versioned module counts and cursor history navigation', () => {
  assert.match(source, /schema_version\?: number/)
  assert.match(source, /total_record_count\?: number/)
  assert.match(source, /manifestModules\(item\)/)
  assert.match(source, /module\.recordCount/)
  assert.match(source, /pagination\.next_cursor/)
  assert.match(source, /historyPageUrl/)
  assert.match(source, /<Button as-child variant="outline">/)
})
