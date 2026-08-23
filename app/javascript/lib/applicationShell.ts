import {
  inject,
  type Component,
  type InjectionKey,
} from 'vue'

export type ApplicationShellNavigationItem = Readonly<{
  href: string
  labelKey: string
  badgeProp?: string
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
