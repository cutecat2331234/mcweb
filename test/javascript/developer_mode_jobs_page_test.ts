import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

function projectSource(relativePath: string) {
  return readFileSync(new URL(`../../${relativePath}`, import.meta.url), 'utf8')
}

test('background jobs page uses Arco and explains Developer Mode scheduling', () => {
  const source = projectSource('app/javascript/pages/Admin/System/Jobs/Index.vue')

  assert.match(source, /<a-page-header/)
  assert.match(source, /<a-alert/)
  assert.match(source, /<a-card/)
  assert.match(source, /<a-descriptions/)
  assert.match(source, /<a-tag/)
  assert.match(source, /<a-button/)
  assert.match(source, /v-if="developerMode\.enabled"/)
  assert.match(source, /automaticRegistration/)
  assert.match(
    source,
    /<a-button type="primary" :href="dashboardUrl" data-admin-hard-navigation>/,
  )
  assert.doesNotMatch(source, /window\.location/)
  assert.doesNotMatch(source, /<(?:input|select|button|table)(?:\s|>)/)
})

test('background jobs warning is translated in English and Chinese', () => {
  const english = projectSource('app/javascript/locales/en.ts')
  const chinese = projectSource('app/javascript/locales/zh-CN.ts')

  for (const source of [english, chinese]) {
    assert.match(source, /jobsPage:\s*\{/)
    assert.match(source, /developerModeTitle:/)
    assert.match(source, /developerModeDescription:/)
    assert.match(source, /automaticRegistration:/)
    assert.match(source, /manualExecution:/)
    assert.match(source, /openDashboard:/)
  }
})
