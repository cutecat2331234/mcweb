import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import {
  KNOWN_SYSTEM_SETTING_KEYS,
  systemSettingBooleanStorage,
  systemSettingGroup,
  systemSettingInputType,
  systemSettingReadOnly,
} from '../../app/javascript/lib/systemSettings.ts'

const pageSource = readFileSync(
  new URL('../../app/javascript/pages/Admin/System/Settings/Show.vue', import.meta.url),
  'utf8',
)

test('system settings use semantic groups and controls', () => {
  assert.equal(systemSettingGroup('site.name'), 'general')
  assert.equal(systemSettingGroup('features.forum.enabled'), 'features')
  assert.equal(systemSettingGroup('forum.bump_cooldown_hours'), 'forum')
  assert.equal(systemSettingGroup('store.shipping_methods'), 'store')
  assert.equal(systemSettingGroup('minecraft.graceful_stop.enabled'), 'minecraft')
  assert.equal(systemSettingGroup('webhook.failure_alert_email'), 'integrations')
  assert.equal(systemSettingGroup('webhook.failure_alert_locale'), 'integrations')
  assert(KNOWN_SYSTEM_SETTING_KEYS.includes('webhook.failure_alert_locale'))

  assert.equal(systemSettingInputType('features.forum.enabled'), 'boolean')
  assert.equal(systemSettingInputType('forum.vapid_private_key'), 'password')
  assert.equal(systemSettingInputType('forum.points.post_created'), 'number')
  assert.equal(systemSettingInputType('store.shipping_methods'), 'textarea')
  assert(systemSettingReadOnly('forum.online_peak_count'))
})

test('boolean settings preserve their backend storage format', () => {
  assert.equal(systemSettingBooleanStorage('features.forum.enabled', true), 'true')
  assert.equal(systemSettingBooleanStorage('features.forum.enabled', false), 'false')
  assert.equal(systemSettingBooleanStorage('forum.auto_close_on_solved', true), '1')
  assert.equal(systemSettingBooleanStorage('forum.auto_close_on_solved', false), '0')
})

test('system settings render localized labels and never promote raw keys to labels', () => {
  assert.doesNotMatch(pageSource, /:label="setting\.key"/)
  assert.doesNotMatch(pageSource, /technicalKey/)
  assert.doesNotMatch(pageSource, /\{ key: setting\.key \}/)
  assert.match(pageSource, /:label="setting\.label"/)
  assert.match(pageSource, /<a-input-search/)
  assert.match(pageSource, /<a-tabs/)
  assert.match(pageSource, /<a-switch/)
  assert.match(pageSource, /<a-input-number/)
  assert.match(pageSource, /<a-input-password/)
  assert.match(pageSource, /<a-textarea/)
  assert.match(pageSource, /changedSettings/)
  assert.match(pageSource, /if \(setting\.sensitive\) form\.settings\[setting\.key\] = ''/)
})
