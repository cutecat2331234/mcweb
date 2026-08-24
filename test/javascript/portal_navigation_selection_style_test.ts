import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

function source(path: string) {
  return readFileSync(resolve(process.cwd(), path), 'utf8')
}

test('portal navigation uses stable library colors without decorative selection bars or press movement', () => {
  const portal = source('app/javascript/layouts/PortalLayout.vue')

  assert.match(portal, /import \{[\s\S]*\bMenu,[\s\S]*\bMenuItem,[\s\S]*\} from '@mcweb\/ui'/m)
  assert.match(portal, /<Menu[\s\S]*?:selected-keys="selectedKey \? \[selectedKey\] : \[\]"/m)
  assert.match(portal, /<MenuItem v-for="item in group\.items" :key="item\.href">/)
  assert.doesNotMatch(portal, /PortalNavLink|PortalNavGroupSection/)
  assert.doesNotMatch(portal, /::before|before:|translate[XY]?\(|\bscale\(|active:scale|transition-all/)
})
