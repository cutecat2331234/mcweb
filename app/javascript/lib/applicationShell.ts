import {
  inject,
  type Component,
  type InjectionKey,
} from 'vue'

export type ApplicationShellNavigationItem = Readonly<{
  href: string
  labelKey: string
  badgeProp?: string
  visibilityProp?: string
  moduleKey?: string
  permissionKey?: string
  permissionAny?: readonly string[]
  capabilityKey?: string
  requiresAuthentication?: boolean
}>

export type ApplicationShellNavigationGroup = Readonly<{
  id: string
  labelKey: string
  items: readonly ApplicationShellNavigationItem[]
}>

export type ApplicationShellAdapter = Readonly<{
  applicationId: string
  brandKey: string
  navigation: readonly ApplicationShellNavigationGroup[]
  accessory?: Component
}>

export type ApplicationShellNavigationContribution = Readonly<{
  contributionId: string
  groups: readonly ApplicationShellNavigationGroup[]
}>

function resolveShellProp(props: unknown, path: string): unknown {
  let value = props
  for (const segment of path.split('.')) {
    if (value === null || typeof value !== 'object'
      || !Object.prototype.hasOwnProperty.call(value, segment)) return undefined
    value = (value as Record<string, unknown>)[segment]
  }
  return value
}

function shellGrantList(pageProps: unknown, path: string): readonly string[] {
  const value = resolveShellProp(pageProps, path)
  return Array.isArray(value) && value.every((entry) => typeof entry === 'string')
    ? value
    : []
}

function hasShellGrant(pageProps: unknown, path: string, grant: string): boolean {
  return shellGrantList(pageProps, path).includes(grant)
}

function hasShellCapability(pageProps: unknown, capability: string): boolean {
  const capabilities = resolveShellProp(pageProps, 'auth.user.admin_capabilities')
  return capabilities !== null
    && typeof capabilities === 'object'
    && Object.prototype.hasOwnProperty.call(capabilities, capability)
    && (capabilities as Record<string, unknown>)[capability] === true
}

export function isApplicationShellNavigationItemVisible(
  item: ApplicationShellNavigationItem,
  pageProps: unknown,
  authenticated: boolean,
): boolean {
  if (item.requiresAuthentication && !authenticated) return false
  if (item.visibilityProp && resolveShellProp(pageProps, item.visibilityProp) !== true) return false
  if (item.moduleKey
    && !hasShellGrant(pageProps, 'auth.user.admin_modules', item.moduleKey)) return false
  if (item.permissionKey
    && !hasShellGrant(pageProps, 'auth.user.admin_permissions', item.permissionKey)) return false
  if (item.permissionAny
    && !item.permissionAny.some((permission) => (
      hasShellGrant(pageProps, 'auth.user.admin_permissions', permission)
    ))) return false
  if (item.capabilityKey
    && !hasShellCapability(pageProps, item.capabilityKey)) return false
  return true
}

function freezeNavigationGroup(
  group: ApplicationShellNavigationGroup,
): ApplicationShellNavigationGroup {
  return Object.freeze({
    ...group,
    items: Object.freeze(group.items.map((item) => Object.freeze({ ...item }))),
  })
}

export function composeApplicationShell(
  applicationId: string,
  base: ApplicationShellAdapter | undefined,
  contributions: readonly ApplicationShellNavigationContribution[],
): ApplicationShellAdapter | undefined {
  if (contributions.length === 0) return base
  if (!base || base.applicationId !== applicationId) {
    throw new Error(`Application ${applicationId} cannot install navigation without its base shell`)
  }
  const groupIds = new Set(base.navigation.map((group) => group.id))
  const contributionGroups = contributions.flatMap(({ contributionId, groups }) => (
    groups.map((group) => {
      if (groupIds.has(group.id)) {
        throw new Error(`Frontend navigation group ${group.id} is already registered`)
      }
      groupIds.add(group.id)
      return freezeNavigationGroup({
        ...group,
        id: `${contributionId}:${group.id}`,
      })
    })
  ))
  return Object.freeze({
    ...base,
    navigation: Object.freeze([
      ...base.navigation.map(freezeNavigationGroup),
      ...contributionGroups,
    ]),
  })
}

export const APPLICATION_SHELL_ADAPTER: InjectionKey<ApplicationShellAdapter> = Symbol(
  'mcweb-application-shell-adapter',
)

export function useApplicationShell(): ApplicationShellAdapter {
  const adapter = inject(APPLICATION_SHELL_ADAPTER)
  if (!adapter) throw new Error('Application shell adapter was not installed')
  return adapter
}
