import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

function source(relativePath: string) {
  return readFileSync(resolve(process.cwd(), relativePath), 'utf8')
}

const accountPage = source('app/javascript/pages/Account/Show.vue')
const profilePage = source('app/javascript/pages/Identity/Profiles/Show.vue')
const passwordPage = source('app/javascript/pages/Identity/Passwords/Edit.vue')

test('account center remains a state dashboard without the repeated action-list wall', () => {
  assert.match(accountPage, /defineOptions\(\{ layout: PortalLayout \}\)/)
  assert.match(accountPage, /<PageHeader/)
  assert.match(accountPage, /<Descriptions/)
  assert.match(accountPage, /<Statistic/)
  assert.match(accountPage, /props\.identity/)
  assert.match(accountPage, /security\.email_verified/)
  assert.match(accountPage, /props\.activity/)
  assert.match(accountPage, /routes\.identityProfile/)
  assert.match(accountPage, /routes\.securityPassword/)
  assert.match(accountPage, /routes\.security/)
  assert.match(accountPage, /routes\.minecraftLink/)
  assert.match(accountPage, /routes\.sessionsManagement/)
  assert.match(accountPage, /routes\.identityDataExports/)
  assert.doesNotMatch(accountPage, /<List/)
  assert.doesNotMatch(accountPage, /components\/ui\//)
  assert.doesNotMatch(accountPage, /hoverable/)
  assert.doesNotMatch(accountPage, /gradient|translate[XY]?\(/i)
})

test('forum-only personal pages retain a compact discoverable entry', () => {
  for (const independentlyRoutedForumDestination of [
    'forumNew',
    'forumUnread',
    'forumWatching',
    'forumBookmarks',
    'forumFollowing',
    'forumWatchedTags',
    'forumBlocks',
    'forumIgnores',
    'forumMuted',
  ]) {
    assert.match(accountPage, new RegExp(`routes\\.${independentlyRoutedForumDestination}`))
  }
  assert.doesNotMatch(accountPage, /routes\.forumPreferences/)
  assert.doesNotMatch(accountPage, /routes\.forumWatchedTagTopics/)
  assert.match(accountPage, /const forumToolGroups: ForumToolGroup\[\]/)
  assert.match(accountPage, /<ArcoLink/)
  assert.match(accountPage, /v-if="forum_enabled"/)
})

test('account self-service pages use existing utility classes instead of inline layout styles', () => {
  for (const page of [accountPage, profilePage, passwordPage]) {
    assert.doesNotMatch(page, /\s(?::style|style)=/)
  }
  assert.match(accountPage, /class="!m-0"/)
  assert.match(accountPage, /class="break-all"/)
  assert.match(accountPage, /class="justify-between"/)
  assert.match(profilePage, /class="max-w-xl"/)
  assert.match(passwordPage, /class="max-w-xl"/)
  assert.match(profilePage, /class="!mb-0"/)
  assert.match(profilePage, /class="mb-4"/)
  assert.match(passwordPage, /class="mb-4"/)
})
