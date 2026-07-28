import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

function source(path: string) {
  return readFileSync(resolve(process.cwd(), path), 'utf8')
}

const page = source('app/javascript/pages/Admin/System/Applications/Index.vue')
const controller = source('app/controllers/admin/system/applications_controller.rb')
const manager = source('lib/mcweb/plugins/marketplace/manager.rb')
const routes = source('config/routes.rb')
const permissionCatalog = source('app/services/identity/permission_catalog.rb')
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
  assert.match(page, /uninstallConfirmation\.value\.trim\(\) === uninstallTarget\.value\.id/)
  assert.match(page, /confirmation: uninstallConfirmation\.value\.trim\(\)/)
  assert.match(page, /expected_version: target\.version/)
  assert.match(page, /expected_sha256: target\.sha256/)
  assert.match(page, /hasVerifiedUninstallIdentity\(plugin\)/)
  assert.match(page, /uninstallRiskTitle/)
})

test('CE plugin package controller only stages uploads and delegates lifecycle to Manager', () => {
  assert.match(controller, /require_permission\("system\.plugins\.manage"\)/)
  assert.match(controller, /SHA256_PATTERN = \/\\A\[0-9a-f\]\{64\}\\z\//)
  assert.match(controller, /Tempfile\.create\(\[ "mcweb-plugin-upload-", "\.zip" \]\)/)
  assert.match(controller, /MAX_PLUGIN_PACKAGE_BYTES = 50\.megabytes/)
  assert.match(controller, /marketplace_manager\.install\(/)
  assert.match(controller, /marketplace_manager\.public_send\([\s\S]*?plugin_id: params\[:plugin_id\]\.to_s/)
  assert.match(controller, /params\[:confirmation\]\.to_s == plugin_id/)
  assert.match(controller, /expected_version: params\[:expected_version\]\.to_s/)
  assert.match(controller, /expected_sha256: params\[:expected_sha256\]\.to_s/)
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

test('CE plugin uninstall revalidates version and package checksum under the lifecycle lock', () => {
  assert.match(manager, /def uninstall\(plugin_id:, expected_version:, expected_sha256:\)/)
  assert.match(manager, /def with_operation[\s\S]*?with_lock do/)

  const transitionStart = manager.indexOf('def transition_to_inactive')
  const transitionEnd = manager.indexOf('def with_operation', transitionStart)
  const transition = manager.slice(transitionStart, transitionEnd)
  assert.ok(transitionStart >= 0 && transitionEnd > transitionStart)
  assert.ok(transition.indexOf('with_operation') < transition.indexOf('validate_uninstall_identity!'))
  assert.ok(transition.indexOf('validate_uninstall_identity!') < transition.indexOf('load_setup_plan'))
})

test('CE plugin management permission comes from the shared system catalog', () => {
  assert.match(
    permissionCatalog,
    /"system\.plugins\.manage"[\s\S]*?app\/controllers\/admin\/system\/applications_controller\.rb/,
  )
  assert.match(accountAccess, /PermissionCatalog\.active_entries/)
  assert.match(accountAccess, /\.group_by\(&:admin_module\)/)
})
