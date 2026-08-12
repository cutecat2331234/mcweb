import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

function source(relativePath: string) {
  return readFileSync(new URL(`../../${relativePath}`, import.meta.url), 'utf8')
}

test('keyboard focus acceptance traverses from a stable document origin with real Tab input', () => {
  const helper = source('test/e2e/support/accessibility.ts')
  const adminSpec = source('test/e2e/admin-quality.spec.ts')

  assert.doesNotMatch(helper, /attempt\s*<\s*8/)
  assert.doesNotMatch(helper, /\.focus\(\)/)
  assert.doesNotMatch(helper, /type Locator/)
  assert.doesNotMatch(adminSpec, /Open Sidekiq dashboard/)
  assert.match(helper, /document\.body\.focus\(\{ preventScroll: true \}\)/)
  assert.match(helper, /document\.activeElement === document\.body/)
  assert.match(helper, /const tabStopBudget =/)
  assert.match(helper, /keyboard\.press\('Tab'\)/)
  assert.match(
    adminSpec,
    /keyboard focus indicator is reachable through real Tab navigation/,
  )
})

test('keyboard focus acceptance requires focus-visible and a computed visual ring', () => {
  const helper = source('test/e2e/support/accessibility.ts')

  assert.match(helper, /matches\(':focus-visible'\)/)
  assert.match(helper, /getComputedStyle\(element\)/)
  assert.match(helper, /indicator\?\.outlineVisible \|\| indicator\?\.shadowVisible/)
  assert.match(helper, /outlineColor/)
  assert.match(helper, /boxShadow/)
  assert.match(helper, /visibleInteractive/)
})
