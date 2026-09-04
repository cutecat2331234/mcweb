import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

import en from '../../app/javascript/locales/en.ts'
import zhCN from '../../app/javascript/locales/zh-CN.ts'

function source(relativePath: string) {
  return readFileSync(new URL(`../../${relativePath}`, import.meta.url), 'utf8')
}

const lifecycle = source('app/javascript/components/admin/minecraft/WorldRestoreLifecycle.vue')
const serverShow = source('app/javascript/pages/Admin/Minecraft/Servers/Show.vue')
const serverController = source('app/controllers/admin/minecraft/servers_controller.rb')
const worldRestoresController = source('app/controllers/admin/minecraft/world_restores_controller.rb')
const cancelService = source('app/services/minecraft/cancel_world_restore.rb')
const routes = source('config/routes.rb')
const executeService = source('app/services/minecraft/execute_world_restore.rb')

test('managed world restore uses the shared Arco UI and an explicit three-phase safety flow', () => {
  assert.match(lifecycle, /from '@mcweb\/ui'/)
  assert.match(lifecycle, /<a-steps[\s\S]*stepPlan[\s\S]*stepAuthorize[\s\S]*stepExecute/)
  assert.match(lifecycle, /createIdempotencyKey/)
  assert.match(lifecycle, /password: password\.value/)
  assert.match(lifecycle, /code: verificationCode\.value/)
  assert.match(lifecycle, /authorization_token: authorizationToken\.value/)
  assert.match(lifecycle, /confirmation\.value === requiredConfirmation\.value/)
  assert.match(lifecycle, /<a-input-password/)
  assert.match(lifecycle, /<a-textarea/)
  assert.match(lifecycle, /<a-table/)
  assert.doesNotMatch(lifecycle, /<(?:input|select|button|table)(?:\s|>)/)
  assert.doesNotMatch(lifecycle, /archive_path|source_path|target_path|backup_directory/)
})

test('server controls expose managed lifecycle props and remain blocked during restore recovery', () => {
  assert.match(serverShow, /<WorldRestoreLifecycle :model="worldSafety"/)
  assert.match(serverShow, /:disabled="worldSafety\.start_blocked"/)
  assert.doesNotMatch(serverShow, /archivePath|backupDirectory|backup_directory/)
  assert.match(serverController, /worldSafety: world_safety_props\(@server\)/)
  assert.match(serverController, /minecraft\.world_backups\.manage/)
  assert.match(serverController, /minecraft\.world_restores\.execute/)
  assert.doesNotMatch(serverController, /def backup_world|def restore_world|backup_directory:/)
  assert.match(routes, /resources :world_backups, only: :create/)
  assert.match(routes, /resources :world_restores, only: :create[\s\S]*post :authorize[\s\S]*post :execute/)
  assert.match(routes, /post :execute[\s\S]*post :cancel[\s\S]*post :plan_recovery/)
  assert.match(routes, /post :plan_recovery[\s\S]*post :authorize_recovery[\s\S]*post :execute_recovery/)
  assert.match(routes, /post :cancel_recovery[\s\S]*post :takeover_recovery/)
})

test('server-owned resumability keeps local clock skew out of restore reachability', () => {
  assert.doesNotMatch(lifecycle, /Date\.now\(\)/)
  assert.match(lifecycle, /props\.model\.plans\.find\(\(candidate\) => candidate\.resumable\)/)
  assert.match(lifecycle, /plan\?\.resumable[\s\S]*continuePlanTitle/)
  assert.match(lifecycle, /record\.resumable[\s\S]*continuePlan\(record\)/)
  assert.match(serverController, /resumable: resumable[\s\S]*is_expired: expired/)
  assert.match(serverController, /plan\.expires_at <= now/)
  assert.match(worldRestoresController, /resumable: resumable[\s\S]*is_expired: expired/)
  assert.match(worldRestoresController, /resolution\.expired_by_time\?\(now\)/)
})

test('restore state conflicts clear local selections and reload authoritative props', () => {
  assert.match(lifecycle, /function stateConflict\(error: unknown\)/)
  assert.match(lifecycle, /world_restore_plan_expired/)
  assert.match(lifecycle, /world_restore_recovery_resolution_expired/)
  assert.match(lifecycle, /function clearPlanSelection\(\)[\s\S]*plan\.value = null[\s\S]*selectedBackupId\.value = ''/)
  assert.match(lifecycle, /function clearRecoverySelection\(\)[\s\S]*recoveryResolution\.value = null/)
  assert.match(lifecycle, /if \(scope === 'plan'\) clearPlanSelection\(\)[\s\S]*refresh\(\)/)
  assert.match(lifecycle, /router\.reload\(\{ only: \['worldSafety'\]/)
})

test('owned unqueued restore plans expose an audited idempotent cancellation contract', () => {
  assert.match(routes, /post :cancel/)
  assert.match(worldRestoresController, /CancelWorldRestore\.call/)
  assert.match(worldRestoresController, /expected_lock_version: params\[:expected_lock_version\]/)
  assert.match(lifecycle, /plan\.value\.cancel_url/)
  assert.match(lifecycle, /request_id: cancelRequestId\.value/)
  assert.match(lifecycle, /expected_lock_version: plan\.value\.lock_version/)
  assert.match(cancelService, /@actor\.id == @plan\.actor_id/)
  assert.match(cancelService, /@plan\.lock![\s\S]*status\.in\?\(%w\[planned authorized\]\)/)
  assert.match(cancelService, /@plan\.expires_at <= now/)
  assert.match(cancelService, /status: "cancelled"/)
  assert.match(cancelService, /result_summary:[\s\S]*"cancellation" => cancellation/)
  assert.match(cancelService, /minecraft\.world_restore\.cancelled/)
  assert.match(cancelService, /AuditLog\.record!/)
  assert.doesNotMatch(cancelService, /destroy!?|delete(?:_all)?/)
})

test('recovery resolution uses Arco controls and node-proven step-up execution', () => {
  assert.match(lifecycle, /recoveryRiskBody/)
  assert.match(lifecycle, /expected_plan_lock_version: recoveryPlan\.value\.lock_version/)
  assert.match(lifecycle, /expected_lock_version: recoveryResolution\.value\.lock_version/)
  assert.match(lifecycle, /resolution_action: recoveryAction\.value/)
  assert.match(lifecycle, /authorization_token: recoveryAuthorizationToken\.value/)
  assert.match(lifecycle, /<a-select[\s\S]*<a-input-password[\s\S]*<a-textarea/)
  assert.match(lifecycle, /expected_plan_lock_version: recoveryPlan\.value\.lock_version/)
  assert.match(lifecycle, /expected_resolution_lock_version: recoveryResolution\.value\.lock_version/)
  assert.match(lifecycle, /manageRecoveryLifecycle\('cancel'\)[\s\S]*manageRecoveryLifecycle\('takeover'\)/)
  assert.match(lifecycle, /recoveryResolution\.value\.cancel_url[\s\S]*recoveryResolution\.value\.takeover_url/)
  assert.doesNotMatch(lifecycle, /<(?:input|select|button|table)(?:\s|>)/)
})

test('execute serializes the final contract check with plan and server configuration locks', () => {
  assert.match(executeService, /@plan\.lock![\s\S]*Minecraft::Server\.lock\.find/)
  assert.match(executeService, /Minecraft::Server\.lock\.find[\s\S]*Minecraft::Node\.lock\.find[\s\S]*Minecraft::WorldBackup\.lock\.find/)
  assert.match(executeService, /current_contract_error\([\s\S]*server: server[\s\S]*node: node[\s\S]*backup: backup[\s\S]*EnqueueNodeOperation\.call/)
  assert.match(serverController, /def update[\s\S]*@server\.lock![\s\S]*@server\.assign_attributes/)
})

test('world safety status, phase, blocker, and purpose vocabularies stay symmetric', () => {
  const english = en.adminMinecraft.worldSafety
  const chinese = zhCN.adminMinecraft.worldSafety

  assert.deepEqual(Object.keys(english.statuses).sort(), Object.keys(chinese.statuses).sort())
  assert.deepEqual(Object.keys(english.phases).sort(), Object.keys(chinese.phases).sort())
  assert.deepEqual(Object.keys(english.blockers).sort(), Object.keys(chinese.blockers).sort())
  assert.deepEqual(Object.keys(english.purposes).sort(), Object.keys(chinese.purposes).sort())
  assert.equal(english.phases.recovery_required.length > 0, true)
  assert.equal(chinese.blockers.restore_capability_missing.length > 0, true)
})
