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
const routes = source('config/routes.rb')

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
