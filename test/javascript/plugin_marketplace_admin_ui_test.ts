import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

function source(path: string) {
  return readFileSync(resolve(process.cwd(), path), 'utf8')
}

const page = source('app/javascript/pages/Admin/System/Applications/Index.vue')
const controller = source('app/controllers/admin/system/applications_controller.rb')
const routes = source('config/routes.rb')
const seeds = source('db/seeds.rb')
const accountAccess = source('app/services/identity/account_access.rb')

test('CE plugin package UI exposes verified upload lifecycle and operation history', () => {
  assert.match(page, /useForm<\{[\s\S]*?plugin_package: File \| null/)
  assert.match(page, /<a-upload[\s\S]*?:auto-upload="false"[\s\S]*?accept="\.zip,application\/zip"/)
  assert.match(page, /admin\.applications\.marketplace\.checksumHint/)
  assert.match(page, /forceFormData: true/)
  assert.match(page, /changePluginState\('enable'/)
  assert.match(page, /changePluginState\('disable'/)
  assert.match(page, /router\.delete\(props\.pluginActions\.uninstall/)
  assert.match(page, /pluginMarketplace\.operations/)
  assert.match(page, /uninstallConfirmMessage/)
})

test('CE plugin package controller only stages uploads and delegates lifecycle to Manager', () => {
  assert.match(controller, /require_permission\("system\.plugins\.manage"\)/)
  assert.match(controller, /SHA256_PATTERN = \/\\A\[0-9a-f\]\{64\}\\z\//)
  assert.match(controller, /Tempfile\.create\(\[ "mcweb-plugin-upload-", "\.zip" \]\)/)
  assert.match(controller, /MAX_PLUGIN_PACKAGE_BYTES = 50\.megabytes/)
  assert.match(controller, /marketplace_manager\.install\(/)
  assert.match(controller, /marketplace_manager\.public_send\(action, plugin_id:/)
  assert.match(controller, /def safe_marketplace_message/)
  assert.doesNotMatch(controller, /params\[:package_path\]/)
  assert.doesNotMatch(controller, /File\.(?:open|read|binread)\(params/)

  for (const route of [
    'post :install_plugin',
    'post :enable_plugin',
    'post :disable_plugin',
    'delete :uninstall_plugin',
  ]) {
    assert.match(routes, new RegExp(route.replace(' ', '\\s+')))
  }
})

test('CE plugin management permission is seeded and assigned to the system module', () => {
  assert.match(seeds, /key: "system\.plugins\.manage"/)
  assert.match(accountAccess, /system\.settings\.manage system\.plugins\.manage/)
})
