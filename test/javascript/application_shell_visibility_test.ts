import assert from 'node:assert/strict'
import test from 'node:test'

import {
  isApplicationShellNavigationItemVisible,
  type ApplicationShellNavigationItem,
} from '../../app/javascript/lib/applicationShell.ts'

const authorizedProps = {
  auth: {
    user: {
      admin_modules: ['pvp'],
      admin_permissions: ['pvp.settings.read', 'pvp.seasons.read'],
      admin_capabilities: { 'pvp.operations.read': true },
    },
  },
  feature_flags: { pvp: true },
}

function item(
  requirements: Partial<ApplicationShellNavigationItem>,
): ApplicationShellNavigationItem {
  return {
    href: '/admin/pvp',
    labelKey: 'pvp.admin.navigation',
    ...requirements,
  }
}

test('application shell navigation authorization grants only declared server capabilities', () => {
  assert.equal(isApplicationShellNavigationItemVisible(item({}), authorizedProps, true), true)
  assert.equal(isApplicationShellNavigationItemVisible(item({
    visibilityProp: 'feature_flags.pvp',
    moduleKey: 'pvp',
    permissionKey: 'pvp.settings.read',
    permissionAny: ['pvp.missing', 'pvp.seasons.read'],
    capabilityKey: 'pvp.operations.read',
    requiresAuthentication: true,
  }), authorizedProps, true), true)
})

test('application shell navigation authorization fails closed for every missing grant', () => {
  assert.equal(isApplicationShellNavigationItemVisible(
    item({ requiresAuthentication: true }), authorizedProps, false,
  ), false)
  assert.equal(isApplicationShellNavigationItemVisible(
    item({ visibilityProp: 'feature_flags.missing' }), authorizedProps, true,
  ), false)
  assert.equal(isApplicationShellNavigationItemVisible(
    item({ moduleKey: 'missing' }), authorizedProps, true,
  ), false)
  assert.equal(isApplicationShellNavigationItemVisible(
    item({ permissionKey: 'missing' }), authorizedProps, true,
  ), false)
  assert.equal(isApplicationShellNavigationItemVisible(
    item({ permissionAny: ['missing.one', 'missing.two'] }), authorizedProps, true,
  ), false)
  assert.equal(isApplicationShellNavigationItemVisible(
    item({ capabilityKey: 'missing' }), authorizedProps, true,
  ), false)
  assert.equal(isApplicationShellNavigationItemVisible(
    item({ moduleKey: 'pvp' }), { auth: { user: { admin_modules: 'pvp' } } }, true,
  ), false)
})
