import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

test('shared Arco internals remain isolated to the application entries that use them', () => {
  const source = readFileSync(resolve(process.cwd(), 'vite.config.ts'), 'utf8')
  const generatedGroups = source.slice(source.indexOf('...arcoChunkGroups.map'))

  assert.match(generatedGroups, /includeDependenciesRecursively:\s*false/)
  assert.match(generatedGroups, /entriesAware:\s*true/)
  assert.match(generatedGroups, /entriesAwareMergeThreshold:\s*0/)
})
