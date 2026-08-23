import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

function source(path: string) {
  return readFileSync(resolve(process.cwd(), path), 'utf8')
}

test('portal navigation uses stable library colors without decorative selection bars or press movement', () => {
  const link = source('app/javascript/components/portal/PortalNavLink.vue')
  const group = source('app/javascript/components/portal/PortalNavGroupSection.vue')

  assert.match(link, /bg-sidebar-accent text-sidebar-accent-foreground/)
  assert.match(group, /bg-sidebar-accent\/60 text-sidebar-foreground/)
  assert.doesNotMatch(link, /before:|active:scale|transition-all/)
  assert.doesNotMatch(group, /active:scale/)
})
