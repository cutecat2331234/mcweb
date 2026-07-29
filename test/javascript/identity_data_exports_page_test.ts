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
})
