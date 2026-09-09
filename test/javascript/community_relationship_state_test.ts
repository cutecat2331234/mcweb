import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'
import { effectScope } from 'vue'
import {
  createCommunityRelationshipMutation,
  reconcileCommunityRelationshipMutation,
  resetCommunityRelationshipMutation,
  submitCommunityRelationshipMutation,
  type CommunityRelationshipIntent,
  type CommunityRelationshipResponse,
} from '../../app/javascript/lib/communityRelationshipMutation.ts'
import { useCommunityRelationshipList } from '../../app/javascript/lib/useCommunityRelationship.ts'

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

  assert.match(profile, /useCommunityRelationship\(/)
  assert.match(profile, /:disabled="blockState\.processing \|\| !blockState\.revision"/)
  assert.match(profile, /:disabled="ignoreState\.processing \|\| !ignoreState\.revision"/)
  assert.match(profile, /:disabled="followState\.processing \|\| !followState\.revision"/)
  assert.match(profile, /props\.profile\.relationships\?\.block/)
  assert.match(profile, /props\.profile\.relationships\?\.ignore/)
  assert.match(profile, /props\.profile\.relationships\?\.follow/)
  assert.doesNotMatch(profile, /router\.post\(props\.profile\.(?:block|ignore|follow)_url/)

  for (const page of [blocks, ignores, following]) {
    assert.match(page, /useCommunityRelationshipList\(/)
    assert.match(page, /states\.get\(user\.username\)\?\.processing/)
    assert.match(page, /v-for="user in visibleUsers"/)
    assert.match(page, /components\.relationship\.retry/)
  }

  assert.match(hoverCard, /useCommunityRelationship\(/)
  assert.match(hoverCard, /card\.value\?\.follow_relationship/)
  assert.match(hoverCard, /followState\.active \? t\('components\.userHover\.unfollow'\)/)
  assert.match(hoverCard, /:disabled="followState\.processing \|\| loading \|\| !followState\.revision"/)
  assert.match(hoverCard, /request === cardRequest && url === props\.cardUrl/)
  assert.doesNotMatch(hoverCard, /following = !card\.value\.following/)
})

test('relationship lists support valid usernames that collide with Object and Vue proxy keys', () => {
  const users = [ 'constructor', 'toString', '__proto__', 'hasOwnProperty', '__v_isReactive', '__v_raw' ].map((username, index) => ({
    username,
    relationship: { active: true, revision: String(index) },
  }))
  const scope = effectScope()
  const relationshipList = scope.run(() => useCommunityRelationshipList(() => users))

  assert.ok(relationshipList)
  assert.deepEqual(relationshipList.visibleUsers.value.map(user => user.username), users.map(user => user.username))
  for (const user of users) {
    assert.equal(relationshipList.states.get(user.username)?.active, true)
    assert.equal(relationshipList.states.get(user.username)?.revision, user.relationship.revision)
  }
  const remainingUsernames = users.map(user => user.username)
  for (const username of users.map(user => user.username)) {
    const state = relationshipList.states.get(username)
    assert.ok(state)
    state.active = false
    remainingUsernames.shift()
    assert.deepEqual(
      relationshipList.visibleUsers.value.map(user => user.username),
      remainingUsernames,
      `${username} must remain a reactive Map key`,
    )
  }
  scope.stop()
})

function deferred<T>() {
  let resolve!: (value: T) => void
  const promise = new Promise<T>(finish => { resolve = finish })
  return { promise, resolve }
}

test('single flight blocks double clicks and waits for confirmed state before changing the label', async () => {
  const state = createCommunityRelationshipMutation({ active: false, revision: '0' })
  const response = deferred<CommunityRelationshipResponse>()
  const requests: Readonly<CommunityRelationshipIntent>[] = []
  const request = (intent: Readonly<CommunityRelationshipIntent>) => { requests.push(intent); return response.promise }

  const first = submitCommunityRelationshipMutation(state, request)
  assert.equal(state.processing, true)
  assert.equal(state.active, false)
  assert.equal(await submitCommunityRelationshipMutation(state, request), 'busy')
  assert.equal(requests.length, 1)
  assert.deepEqual(requests[0], { desiredState: true, expectedRevision: '0', method: 'put' })

  response.resolve({ ok: true, status: 200, data: { active: true, revision: '1' } })
  assert.equal(await first, 'confirmed')
  assert.equal(state.active, true)
  assert.equal(state.pending, null)
  assert.equal(state.processing, false)

  await submitCommunityRelationshipMutation(state, async intent => {
    assert.deepEqual(intent, { desiredState: false, expectedRevision: '1', method: 'delete' })
    return { ok: true, status: 200, data: { active: false, revision: '2' } }
  })
  assert.equal(state.active, false)
})

test('a timeout after commit retries the same intent even if refreshed props already show the new state', async () => {
  const state = createCommunityRelationshipMutation({ active: false, revision: '0' })
  const requests: Readonly<CommunityRelationshipIntent>[] = []
  await submitCommunityRelationshipMutation(state, async intent => {
    requests.push(intent)
    throw new Error('response lost after server commit')
  })
  assert.equal(state.error, 'retry')
  assert.equal(state.active, false)
  reconcileCommunityRelationshipMutation(state, { active: true, revision: '1' })

  await submitCommunityRelationshipMutation(state, async intent => {
    requests.push(intent)
    return { ok: true, status: 200, data: { active: true, revision: '1', changed: false, replayed: true } }
  })
  assert.strictEqual(requests[0], requests[1])
  assert.equal(requests[1].method, 'put', 'a retry must not invert the now-confirmed state')
  assert.equal(state.revision, '1')
  assert.equal(state.pending, null)
})

test('an uncertain DELETE is never rebased onto a later block and conflict displays the server state', async () => {
  const state = createCommunityRelationshipMutation({ active: true, revision: '1' })
  await submitCommunityRelationshipMutation(state, async () => { throw new Error('timeout') })
  reconcileCommunityRelationshipMutation(state, { active: true, revision: '3' })

  await submitCommunityRelationshipMutation(state, async intent => {
    assert.deepEqual(intent, { desiredState: false, expectedRevision: '1', method: 'delete' })
    return { ok: false, status: 409, data: { active: true, revision: '3' } }
  })
  assert.equal(state.active, true)
  assert.equal(state.revision, '3')
  assert.equal(state.error, 'conflict')
  assert.equal(state.pending, null)
})

test('out of order mutation and page responses cannot replace a newer snapshot', async () => {
  const state = createCommunityRelationshipMutation({ active: false, revision: '8' })
  const response = deferred<CommunityRelationshipResponse>()
  const request = submitCommunityRelationshipMutation(state, () => response.promise)
  reconcileCommunityRelationshipMutation(state, { active: false, revision: '10' })
  response.resolve({ ok: true, status: 200, data: { active: true, revision: '9' } })
  await request
  reconcileCommunityRelationshipMutation(state, { active: true, revision: '8' })

  assert.equal(state.active, false)
  assert.equal(state.revision, '10')
  reconcileCommunityRelationshipMutation(state, { active: true, revision: '9007199254740993' })
  reconcileCommunityRelationshipMutation(state, { active: false, revision: '9007199254740992' })
  assert.equal(state.revision, '9007199254740993')
  assert.equal(state.active, true)
})

test('a late response for a previous profile cannot mutate or unlock the new profile', async () => {
  const state = createCommunityRelationshipMutation({ active: false, revision: '20' })
  const previousResponse = deferred<CommunityRelationshipResponse>()
  const previous = submitCommunityRelationshipMutation(state, () => previousResponse.promise)
  resetCommunityRelationshipMutation(state, { active: false, revision: '0' })
  const nextResponse = deferred<CommunityRelationshipResponse>()
  const next = submitCommunityRelationshipMutation(state, () => nextResponse.promise)

  previousResponse.resolve({ ok: true, status: 200, data: { active: true, revision: '21' } })
  await previous
  assert.equal(state.processing, true)
  assert.equal(state.revision, '0')
  assert.equal(state.active, false)
  nextResponse.resolve({ ok: true, status: 200, data: { active: true, revision: '1' } })
  await next
  assert.equal(state.processing, false)
  assert.equal(state.revision, '1')
})

test('malformed successes and server errors retain the intent rather than claiming success', async () => {
  for (const response of [
    { ok: true, status: 200, data: { active: true } },
    { ok: false, status: 500 },
    { ok: false, status: 409 },
  ]) {
    const state = createCommunityRelationshipMutation({ active: true, revision: '1' })
    assert.equal(await submitCommunityRelationshipMutation(state, async () => response), 'uncertain')
    assert.equal(state.active, true)
    assert.equal(state.pending?.expectedRevision, '1')
    assert.equal(state.pending?.desiredState, false)
    assert.equal(state.error, 'retry')
  }
})

test('missing revisions fail closed and known rejections are not reported as confirmed changes', async () => {
  const missing = createCommunityRelationshipMutation()
  let requests = 0
  await submitCommunityRelationshipMutation(missing, async () => { requests++; return { ok: true, status: 200 } })
  assert.equal(requests, 0)
  const state = createCommunityRelationshipMutation({ active: true, revision: '4' })
  assert.equal(await submitCommunityRelationshipMutation(state, async () => ({ ok: false, status: 403 })), 'rejected')
  assert.equal(state.active, true)
  assert.equal(state.revision, '4')
  assert.equal(state.error, 'failed')
})

test('the browser transport sends the captured revision with CSRF, a timeout and no cached response', () => {
  const transport = source('app/javascript/lib/useCommunityRelationship.ts')
  assert.match(transport, /method: intent\.method\.toUpperCase\(\)/)
  assert.match(transport, /expected_revision: intent\.expectedRevision/)
  assert.match(transport, /\.\.\.csrfHeaders\(\)/)
  assert.match(transport, /controller\.abort\(\), 15_000/)
  assert.match(transport, /cache: 'no-store'/)
  assert.match(transport, /redirect: 'error'/)
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
