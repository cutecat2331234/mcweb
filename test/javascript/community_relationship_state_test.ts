import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'
import {
  beginCommunityRelationshipMutation,
  finishCommunityRelationshipMutation,
} from '../../app/javascript/lib/communityRelationshipMutation.ts'

const root = process.cwd()

function source(path: string): string {
  return readFileSync(resolve(root, path), 'utf8')
}

test('community relationship controls request explicit final states and disable duplicate clicks', () => {
  const profile = source('app/javascript/pages/Community/Users/Show.vue')
  const blocks = source('app/javascript/pages/Community/Blocks/Index.vue')
  const ignores = source('app/javascript/pages/Community/Ignores/Index.vue')
  const following = source('app/javascript/pages/Community/Following/Index.vue')
  const hoverCard = source('app/javascript/components/portal/UserHoverCard.vue')

  assert.match(profile, /router\.put\(props\.profile\.block_url/)
  assert.match(profile, /router\.delete\(props\.profile\.block_url/)
  assert.match(profile, /:disabled="relationshipProcessing\.block"/)
  assert.match(profile, /:disabled="relationshipProcessing\.ignore"/)
  assert.match(profile, /:disabled="relationshipProcessing\.follow"/)
  assert.match(profile, /beginCommunityRelationshipMutation\(blockProcessing, props\.profile\.is_blocked\)/)
  assert.match(profile, /beginCommunityRelationshipMutation\(ignoreProcessing, props\.profile\.is_ignored === true\)/)
  assert.match(profile, /beginCommunityRelationshipMutation\(followProcessing, props\.profile\.is_following\)/)
  assert.doesNotMatch(profile, /router\.post\(props\.profile\.(?:block|ignore|follow)_url/)

  for (const page of [blocks, ignores, following]) {
    assert.match(page, /router\.delete\(/)
    assert.match(page, /:disabled="processingUsers\.has\(user\.username\)"/)
  }

  assert.match(hoverCard, /if \(mutation\.method === 'put'\) router\.put\(/)
  assert.match(hoverCard, /else router\.delete\(/)
  assert.match(hoverCard, /async function reloadCard\(\) \{[\s\S]*?card\.value = null[\s\S]*?await loadCard\(\)/)
  assert.match(hoverCard, /onSuccess: \(\) => \{ void reloadCard\(\) \}/)
  assert.match(hoverCard, /:disabled="followProcessing \|\| loading"/)
  assert.doesNotMatch(hoverCard, /following = !card\.value\.following/)
})

test('community relationship mutation state machine is executable and suppresses overlapping intent', () => {
  const processing = { value: false }

  const establish = beginCommunityRelationshipMutation(processing, false)
  assert.deepEqual(establish, { desiredState: true, method: 'put' })
  assert.equal(processing.value, true)
  assert.equal(beginCommunityRelationshipMutation(processing, false), null)

  finishCommunityRelationshipMutation(processing)
  assert.equal(processing.value, false)

  const remove = beginCommunityRelationshipMutation(processing, true)
  assert.deepEqual(remove, { desiredState: false, method: 'delete' })
  assert.equal(beginCommunityRelationshipMutation(processing, true), null)

  finishCommunityRelationshipMutation(processing)
  assert.equal(processing.value, false)
})

test('legacy toggle routes and service constants are absent', () => {
  const routes = source('config/routes.rb')
  const serviceFiles = [
    'app/services/community/set_user_block.rb',
    'app/services/community/set_user_ignore.rb',
    'app/services/community/set_user_follow.rb',
  ].map(source).join('\n')

  assert.doesNotMatch(routes, /post "users\/:username\/(?:block|ignore|follow)"/)
  assert.doesNotMatch(routes, /member \{ post :follow \}/)
  assert.match(routes, /put "users\/:username\/block"/)
  assert.match(routes, /delete "users\/:username\/block"/)
  assert.match(routes, /member \{ match :follow, via: %i\[put delete\] \}/)
  assert.doesNotMatch(serviceFiles, /ToggleUser(?:Block|Ignore|Follow)/)

  const writer = source('app/services/community/set_user_relationship.rb')
  assert.match(writer, /@relation\.create_or_find_by!/)

  for (const model of [
    source('app/models/community/user_block.rb'),
    source('app/models/community/user_ignore.rb'),
    source('app/models/community/user_follow.rb'),
  ]) {
    assert.doesNotMatch(model, /validates .*uniqueness:/)
    assert.match(model, /unique database index is the concurrency boundary/)
  }
})
