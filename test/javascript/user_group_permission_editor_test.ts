import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

function projectSource(relativePath: string) {
  return readFileSync(new URL(`../../${relativePath}`, import.meta.url), 'utf8')
}

test('identity-group editor uses the structured Arco permission catalog', () => {
  const source = projectSource(
    'app/javascript/pages/Admin/Forum/UserGroups/Form.vue',
  )

  assert.match(source, /permissionCatalog:\s*PermissionDomain\[\]/)
  assert.match(source, /grantablePermissionKeys:\s*string\[\]/)
  assert.match(source, /canManageGroup\?:\s*boolean/)
  assert.match(source, /canAddMembers\?:\s*boolean/)
  assert.match(source, /deleteBlocked\?:/)
  assert.match(source, /<a-tabs default-active-key="details">/)
  assert.match(source, /<a-collapse v-else accordion>/)
  assert.match(source, /<a-checkbox-group[\s\S]*?v-model="form\.user_group\.permissions"/)
  assert.match(source, /:disabled="!canManagePermissions"/)
  assert.match(source, /\.filter\(\(permission\) => permission\.grantable\)/)
  assert.match(source, /!canManagePermissions \|\| !permission\.delegable/)
  assert.match(source, /selectedPermissionsGrantable/)
  assert.match(source, /!props\.canManageGroup/)
  assert.match(source, /!initialPrimaryDefault && !selectedPermissionsGrantable\.value/)
  assert.match(source, /v-if="canAddMembers"/)
  assert.match(source, /canManageMembers && !canAddMembers/)
  assert.match(source, /deleteBlockedMessage/)
  assert.match(source, /v-if="deleteUrl"/)
  assert.match(source, /only:\s*\[\s*'members',\s*'memberPage',\s*'memberTotal'\s*\]/)
  assert.match(source, /<a-pagination/)
  assert.match(source, /permission\.description/)
  assert.match(source, /permission\.key/)
  assert.doesNotMatch(source, /<a-textarea/)
  assert.doesNotMatch(source, /<style(?:\s|>)/)
  assert.doesNotMatch(source, /availablePermissions/)
})

test('identity-group permission editor copy is bilingual', () => {
  const english = projectSource('app/javascript/locales/en.ts')
  const chinese = projectSource('app/javascript/locales/zh-CN.ts')
  const keys = [
    'detailsTab',
    'permissionsTab',
    'permissionScope',
    'permissionScopeHint',
    'permissionCount',
    'selectDomain',
    'clearDomain',
    'noPermissions',
    'permissionsReadOnly',
    'groupReadOnly',
    'membersReadOnly',
    'permissionNotDelegable',
    'permissionRemovalOnly',
    'primaryDefaultRequiresMemberManage',
    'primaryDefaultRequiresGrantable',
    'memberGrantBlocked',
    'deleteBlockedTitle',
    'deleteBlocked',
  ]

  for (const source of [ english, chinese ]) {
    assert.match(source, /userGroupsForm:\s*\{/)
    for (const key of keys) {
      assert.match(source, new RegExp(`\\n\\s+${key}:`))
    }
  }

  assert.match(english, /forumUserGroups:\s*'Identity groups'/)
  assert.match(chinese, /forumUserGroups:\s*'身份组'/)
  assert.doesNotMatch(english, /['"][^'"]*[Uu]ser groups?[^'"]*['"]/)
  assert.doesNotMatch(chinese, /['"][^'"]*用户组[^'"]*['"]/)
})
