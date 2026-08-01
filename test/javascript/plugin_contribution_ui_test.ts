import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const read = (path: string) => readFileSync(path, 'utf8')

test('declarative plugin pages use Arco components without raw HTML rendering', () => {
  const content = read('app/javascript/components/plugins/PluginPageContent.vue')
  const publicPage = read('app/javascript/pages/Plugins/Page.vue')
  const adminPage = read('app/javascript/pages/Admin/Plugins/Page.vue')

  assert.match(content, /<a-card/)
  assert.match(content, /<a-alert/)
  assert.match(content, /<a-descriptions/)
  assert.doesNotMatch(content, /v-html/)
  assert.match(publicPage, /WebsiteLayout/)
  assert.match(adminPage, /AdminLayout/)
  assert.match(adminPage, /<a-row justify="center">/)
  assert.match(adminPage, /<a-col :xs="24" :md="22" :xl="20">/)
  assert.match(adminPage, /<a-space direction="vertical" :size="16" fill>/)
  assert.doesNotMatch(
    adminPage,
    /<style\b|\sclass=|\s:class=|\sstyle=|\s:style=/,
  )
})

test('plugin navigation and targeted slots are composed into shared layouts', () => {
  const website = read('app/javascript/layouts/WebsiteLayout.vue')
  const admin = read('app/javascript/layouts/ArcoAdminLayout.vue')
  const slots = read('app/javascript/components/plugins/PluginUiSlots.vue')

  assert.match(website, /plugin_contributions/)
  assert.match(admin, /plugin_contributions/)
  assert.match(admin, /<PluginUiSlots/)
  assert.match(slots, /<a-card/)
  assert.doesNotMatch(slots, /v-html/)
})
