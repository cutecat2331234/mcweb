import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const source = readFileSync('scripts/start-system-e2e.mjs', 'utf8')

test('explicit E2E database URLs cannot be shadowed by local configuration', () => {
  assert.match(source, /databaseName\.endsWith\(DEFAULT_TEST_SUFFIX\)/)
  assert.match(source, /environment\.DATABASE_URL = databaseUrl\.toString\(\)/)
  assert.match(source, /system-e2e-no-local-config-\$\{process\.pid\}\.yml/)
  assert.match(source, /if \(existsSync\(isolatedLocalConfig\)\)/)
  assert.match(source, /environment\.MCWEB_LOCAL_CONFIG_PATH = isolatedLocalConfig/)
})
