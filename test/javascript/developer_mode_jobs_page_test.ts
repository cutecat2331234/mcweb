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
  assert.match(source, /<a-statistic/)
  assert.match(source, /<a-progress/)
  assert.match(source, /<a-table/)
  assert.match(source, /v-if="developerMode\.enabled"/)
  assert.match(source, /automaticRegistration/)
  assert.match(source, /queueSnapshot\.oldest_wait_seconds/)
  assert.match(source, /queueSnapshot\.utilization_percent/)
  assert.match(source, /workerHeartbeat\.fresh_count/)
  assert.match(source, /workerHeartbeat\.latest_at/)
  assert.match(source, /data-testid="redis-recovery-snapshot"/)
  assert.match(source, /redisRecovery\.database_fallback/)
  assert.match(source, /redisRecovery\.pending_intents/)
  assert.match(source, /redisRecovery\.last_recovery_handoff_at/)
  assert.match(source, /redisRecoveryCopy\.handoffNote/)
  assert.match(source, /const \{ t, te, locale \} = useI18n\(\)/)
  assert.match(source, /new Intl\.DateTimeFormat\(locale\.value,/)
  assert.doesNotMatch(source, /new Intl\.DateTimeFormat\(undefined,/)
  assert.match(
    source,
    /<a-button type="primary" :href="adminRoutes\.sidekiq" long>/,
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
    assert.match(source, /queue:\s*\{/)
    assert.match(source, /oldestWait:/)
    assert.match(source, /unavailableDescription:/)
    assert.match(source, /heartbeatStatus:/)
  }
})
