import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

const page = readFileSync(
  resolve(process.cwd(), 'app/javascript/pages/Account/Show.vue'),
  'utf8',
)
const routes = readFileSync(resolve(process.cwd(), 'app/javascript/lib/routes.ts'), 'utf8')
const staffLayout = readFileSync(resolve(process.cwd(), 'app/javascript/layouts/StaffLayout.vue'), 'utf8')

test('account center uses the shared Portal shell and Arco components for grouped existing tools', () => {
  assert.match(page, /defineOptions\(\{ layout: PortalLayout \}\)/)
  assert.match(page, /from '@mcweb\/ui'/)
  assert.match(page, /<PageHeader/)
  assert.match(page, /<Card/)
  assert.match(page, /<Grid/)
  assert.match(page, /accountCenter\.groups\.\$\{group\.key\}/)

  for (const route of [
    'routes.forumNew',
    'routes.forumUnread',
    'routes.forumWatching',
    'routes.forumFollowing',
    'routes.forumWatchedTags',
    'routes.forumWatchedTagTopics',
    'routes.forumBookmarks',
    'routes.forumMessages',
    'routes.forumDrafts',
    'routes.forumPreferences',
    'routes.forumBlocks',
    'routes.forumIgnores',
    'routes.forumMuted',
    'routes.security',
    'routes.sessionsManagement',
    'routes.identityDataExports',
  ]) {
    assert.match(page, new RegExp(route.replace('.', '\\.')))
  }

  assert.match(page, /if \(props\.minecraft_enabled\)/)
  assert.match(page, /routes\.minecraftLink/)
  assert.match(page, /props\.forum_enabled \? \[/)
  assert.match(page, /if \(props\.forum_enabled\)/)
  assert.doesNotMatch(page, /components\/ui\//)
})

test('account center route and staff return controls point to the whole application', () => {
  assert.match(routes, /account: `\$\{appPrefix\}\/account`/)
  assert.equal((staffLayout.match(/visit\(routes\.app\)/g) || []).length, 2)
  assert.doesNotMatch(staffLayout, /visit\(routes\.forum\)/)
})
