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
  assert.match(page, /uninstallConfirmation\.value\.trim\(\) === uninstallTarget\.value\.id/)
  assert.match(page, /confirmation: uninstallConfirmation\.value\.trim\(\)/)
  assert.match(page, /expected_version: target\.version/)
  assert.match(page, /expected_sha256: target\.sha256/)
  assert.match(page, /data_mode: uninstallDataMode\.value/)
  assert.match(page, /value="preserve_data"/)
  assert.match(page, /value="purge_data"/)
  assert.match(page, /checkPluginHealth\(plugin\.id\)/)
  assert.match(page, /recoverPlugin\(plugin\)/)
  assert.match(page, /props\.pluginActions\.recover/)
  assert.match(page, /rollbackPlugin\(plugin\)/)
  assert.match(page, /props\.pluginActions\.rollback/)
  assert.match(page, /plugin\.rollback_available/)
  assert.match(page, /props\.pluginActions\.reconcileCatalog/)
  assert.match(page, /pluginCatalog\.releases/)
  assert.match(page, /selectedCatalogRelease/)
  assert.match(page, /admin\.applications\.catalog\.findings/)
  assert.match(page, /v-model="installForm\.dry_run"/)
  assert.match(page, /v-model="installForm\.maintenance_mode"/)
  assert.match(page, /dry_run: installForm\.dry_run/)
  assert.match(page, /maintenance_mode: installForm\.maintenance_mode/)
  assert.match(page, /import AdminLayout from '@\/layouts\/AdminLayout\.vue'/)
  assert.match(page, /hasVerifiedUninstallIdentity\(plugin\)/)
  assert.match(page, /fileHealthSummary/)
  assert.match(page, /pluginRuntimeGenerations\.generations/)
  assert.match(page, /admin\.applications\.generations\.requiredAcksValue/)
  assert.match(page, /generation\.acknowledgements/)
  assert.match(page, /plugin\.contribution_descriptors/)
  assert.match(page, /contributionTypeLabel/)
  assert.match(page, /admin\.applications\.contributions\.conflicts/)
  assert.match(page, /pluginLifecycle\.installations/)
  assert.match(page, /pluginLifecycle\.runs/)
  assert.match(page, /selectedLifecycleRun = record/)
  assert.match(page, /<Drawer[\s\S]*?selectedLifecycleRun\.steps/)
  assert.match(page, /<TimelineItem/)
  assert.match(controller, /def plugin_lifecycle_snapshot/)
  assert.match(controller, /PluginLifecycleRun\.includes\(:actor, :steps\)\.recent_first\.limit\(50\)/)
})

test('CE plugin package controller only stages uploads and delegates lifecycle to Manager', () => {
  assert.match(controller, /PLUGIN_ACTION_PERMISSIONS/)
  assert.match(controller, /plugin_permission\?\(permission\)/)
  assert.match(controller, /LEGACY_PLUGIN_PERMISSION = "system\.plugins\.manage"/)
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
    'post :recover_plugin',
    'post :rollback_plugin',
    'post :health_plugin',
    'post :reconcile_plugin_catalog',
    'delete :uninstall_plugin',
  ]) {
    assert.match(routes, new RegExp(route.replace(' ', '\\s+')))
  }
})

test('CE plugin uninstall revalidates version and package checksum under the lifecycle lock', () => {
  assert.match(
    manager,
    /def uninstall\(plugin_id:, expected_version:, expected_sha256:,[\s\S]*?data_mode:/,
  )
  assert.match(manager, /FileHealth\.check/)
  assert.match(manager, /def with_operation[\s\S]*?with_lock do/)

  const transitionStart = manager.indexOf('def transition_to_inactive')
  const transitionEnd = manager.indexOf('def with_operation', transitionStart)
  const transition = manager.slice(transitionStart, transitionEnd)
  assert.ok(transitionStart >= 0 && transitionEnd > transitionStart)
  assert.ok(transition.indexOf('with_operation') < transition.indexOf('validate_uninstall_identity!'))
  assert.ok(transition.indexOf('validate_uninstall_identity!') < transition.indexOf('load_setup_plan'))
})

test('CE plugin lifecycle permissions come from the shared system catalog', () => {
  for (const permission of [
    'system.plugins.view',
    'system.plugins.install',
    'system.plugins.enable',
    'system.plugins.disable',
    'system.plugins.diagnostics',
    'system.plugins.recover',
    'system.plugins.rollback',
    'system.plugins.uninstall_preserve',
    'system.plugins.uninstall_purge',
  ]) {
    assert.match(permissionCatalog, new RegExp(`"${permission.replaceAll('.', '\\.')}"`))
  }
  assert.match(accountAccess, /PermissionCatalog\.active_entries/)
  assert.match(accountAccess, /\.group_by\(&:admin_module\)/)
})
