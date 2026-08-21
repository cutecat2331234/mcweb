import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

const page = readFileSync(
  resolve(process.cwd(), 'app/javascript/pages/Identity/Profiles/Show.vue'),
  'utf8',
)

test('profile self-service uses Arco fields and synchronizes the shared locale preference', () => {
  assert.match(page, /from '@mcweb\/ui'/)
  assert.match(page, /<Form/)
  assert.match(page, /<Input/)
  assert.match(page, /<Select/)
  assert.match(page, /routes\.identityProfile/)
  assert.match(page, /await preloadAppLocale\(selectedLocale\)/)
  assert.match(page, /writeSharedAppLocale\(selectedLocale\)/)
  assert.match(page, /display_name/)
  assert.match(page, /locale/)
  assert.doesNotMatch(page, /time_zone/)
  assert.doesNotMatch(page, /components\/ui\//)
  assert.doesNotMatch(page, /gradient|translate[XY]?\(/i)
})
