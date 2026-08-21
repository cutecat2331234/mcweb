import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

function source(path: string): string {
  return readFileSync(resolve(process.cwd(), path), 'utf8')
}

test('private-message drafts close only after the server echoes the matching edit token', () => {
  const page = source('app/javascript/pages/Community/Messages/Show.vue')

  assert.match(page, /edit_token:\s*editToken/)
  assert.match(page, /flash\?\.message_edit_succeeded === editToken\) cancelEdit\(\)/)
  assert.doesNotMatch(page, /onSuccess:\s*\(\)\s*=>\s*cancelEdit\(\)/)
  assert.match(page, /v-if="editError"\s+role="alert"/)
})

test('profile-wall drafts close only after the server echoes the matching edit token', () => {
  const page = source('app/javascript/pages/Community/Users/Show.vue')

  assert.match(page, /edit_token:\s*editToken/)
  assert.match(page, /flash\?\.profile_wall_edit_succeeded === editToken\) cancelWallEdit\(\)/)
  assert.doesNotMatch(page, /onSuccess:\s*cancelWallEdit/)
  assert.match(page, /v-if="editingWallError"\s+role="alert"/)
})

test('forum-post drafts close only after the server echoes the matching edit token', () => {
  const page = source('app/javascript/pages/Community/Topics/Show.vue')

  assert.match(page, /expected_revision:\s*post\.revision/)
  assert.match(page, /edit_token:\s*editToken/)
  assert.match(page, /flash\?\.post_edit_succeeded === editToken\) cancelEdit\(\)/)
  assert.doesNotMatch(page, /onSuccess:\s*\(\)\s*=>\s*cancelEdit\(\)/)
})
