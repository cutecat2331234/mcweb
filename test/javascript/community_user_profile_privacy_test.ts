import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

const source = readFileSync(
  resolve(process.cwd(), 'app/javascript/pages/Community/Users/Show.vue'),
  'utf8',
)
const usersController = readFileSync(
  resolve(process.cwd(), 'app/controllers/community/users_controller.rb'),
  'utf8',
)
const membersController = readFileSync(
  resolve(process.cwd(), 'app/controllers/community/members_controller.rb'),
  'utf8',
)

test('private profile counters disappear instead of rendering as false zeroes', () => {
  assert.match(source, /v-if="profile\.forum_points !== undefined"/)
  assert.match(source, /v-if="profile\.orders_count !== undefined"/)
  assert.doesNotMatch(source, /profile\.forum_points \?\? 0/)
  assert.doesNotMatch(source, /profile\.orders_count \?\? 0/)
})

test('profile owner receives an explicit activity-summary opt-in control', () => {
  assert.match(source, /const activityPrivacyForm = useForm/)
  assert.match(source, /forum_profile_activity_public: props\.profile\.forum_profile_activity_public === true/)
  assert.match(source, /profileEditPanel === 'privacy'/)
  assert.match(source, /v-model="activityPrivacyForm\.user\.forum_profile_activity_public"/)
  assert.match(source, /@submit(?:\.prevent)?="saveActivityPrivacy"/)
  assert.match(
    source,
    /activityPrivacyForm\.patch\(`\/app\/forum\/users\/\$\{props\.profile\.username\}`/,
  )
  assert.match(source, /userProfile\.activityPrivacy\.description/)
})

test('viewer-scoped profile activity is encrypted in Inertia history', () => {
  assert.match(usersController, /render inertia: "Community\/Users\/Show"[\s\S]*encrypt_history: true/)
  assert.match(membersController, /render inertia: "Community\/Members\/Index"[\s\S]*encrypt_history: true/)
})
