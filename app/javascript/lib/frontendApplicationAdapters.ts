import type { Component, DefineComponent } from 'vue'

import {
  assertFrontendComponent,
  requireFrontendApplication,
  type FrontendDraftContract,
} from '@/lib/frontendApplications'
import {
  installFrontendDraftAdapter,
  isFrontendDraftAdapter,
  type FrontendDraftAdapter,
} from '@/lib/frontendDrafts'
import { registerFrontendLocaleDomain } from '@/lib/i18n'
import type { AppLocale } from '@/lib/i18nRuntime'
import type {
  ApplicationShellNavigationContribution,
  ApplicationShellNavigationGroup,
} from '@/lib/applicationShell'

export type FrontendPageLoader = () => Promise<DefineComponent | { default: DefineComponent }>

export type FrontendApplicationAdapter = Readonly<{
  applicationId: string
  contributionId: string
  pages?: Readonly<Record<string, FrontendPageLoader>>
  localeDomains?: Readonly<Record<
    string,
    Record<AppLocale, () => Promise<{ default: Record<string, unknown> }>>
  >>
  styleModules?: Readonly<Record<string, () => Promise<unknown>>>
  errorBoundary?: Readonly<{
    name: string
    component: Component
  }>
  draftAdapter?: FrontendDraftAdapter
  navigation?: readonly ApplicationShellNavigationGroup[]
  install?: () => void | VoidFunction
}>

type AdapterModule = {
  default?: FrontendApplicationAdapter
}

function runCleanupStack(cleanup: VoidFunction[]): void {
  while (cleanup.length > 0) {
    const remove = cleanup.pop()
    try {
      remove?.()
    } catch (error) {
      console.error('[McWeb] frontend adapter cleanup failed', error)
    }
  }
}

function canonicalAdapterModulePath(modulePath: string): string {
  const normalized = modulePath.replaceAll('\\', '/')
  const marker = 'frontend-application-adapters/'
  const markerIndex = normalized.indexOf(marker)
  if (markerIndex < 0) {
    throw new Error(`Frontend adapter is outside the adapter root: ${modulePath}`)
  }

  return `app/javascript/${normalized.slice(markerIndex)}`
}

function adapterValue(modulePath: string, value: unknown): FrontendApplicationAdapter {
  if (!value || typeof value !== 'object') {
    throw new Error(`Frontend adapter module has no exports: ${modulePath}`)
  }

  const adapter = (value as AdapterModule).default
  if (!adapter || typeof adapter !== 'object') {
    throw new Error(`Frontend adapter module requires a default adapter export: ${modulePath}`)
  }
  if (!adapter.applicationId || !adapter.contributionId) {
    throw new Error(`Frontend adapter module requires applicationId and contributionId: ${modulePath}`)
  }

  return adapter
}

function draftContractsMatch(
  left: FrontendDraftContract | undefined,
  right: FrontendDraftContract | null,
): boolean {
  if (!left || !right) return !left && !right
  return left.capability === right.capability
    && left.keyNamespace === right.keyNamespace
    && left.version === right.version
    && left.userScoped === right.userScoped
    && left.resourceScoped === right.resourceScoped
    && left.offlineRecovery === right.offlineRecovery
    && left.clearOnSubmit === right.clearOnSubmit
}

function navigationSignature(
  groups: readonly ApplicationShellNavigationGroup[],
  contributionId: string,
): string {
  const groupIds = new Set<string>()
  return JSON.stringify(groups.map((group) => {
    if (!group || typeof group !== 'object' || typeof group.id !== 'string'
      || typeof group.labelKey !== 'string' || !Array.isArray(group.items)
      || groupIds.has(group.id)) {
      throw new Error(`Frontend adapter ${contributionId} has invalid navigation groups`)
    }
    groupIds.add(group.id)
    return {
      id: group.id,
      labelKey: group.labelKey,
      items: group.items.map((item) => {
        if (!item || typeof item !== 'object' || typeof item.href !== 'string'
          || typeof item.labelKey !== 'string'
          || (item.badgeProp !== undefined && typeof item.badgeProp !== 'string')
          || (item.visibilityProp !== undefined && typeof item.visibilityProp !== 'string')
          || (item.requiresAuthentication !== undefined
            && typeof item.requiresAuthentication !== 'boolean')) {
          throw new Error(`Frontend adapter ${contributionId} has invalid navigation items`)
        }
        return {
          href: item.href,
          labelKey: item.labelKey,
          badgeProp: item.badgeProp ?? null,
          visibilityProp: item.visibilityProp ?? null,
          requiresAuthentication: item.requiresAuthentication ?? null,
        }
      }),
    }
  }))
}

function canonicalPagePath(pagePath: string, pageRoots: readonly string[]): string {
  const normalized = pagePath.replaceAll('\\', '/')
  const candidates = [normalized.replace(/^\/?/, ''), normalized.replace(/^(?:\.\.\/)+/, '')]
  const localRelative = normalized.match(/^(?:\.\.\/)+pages\/(.+)$/)?.[1]
  if (localRelative) candidates.push(`app/javascript/pages/${localRelative}`)
  let relative: string | null = null
  for (const root of pageRoots) {
    const prefix = `${root}/`
    const candidate = candidates.find((entry) => entry.startsWith(prefix))
    if (candidate) {
      relative = candidate.slice(prefix.length)
      break
    }
  }
  if (!relative || !relative.endsWith('.vue') || relative.includes('..')
    || relative.startsWith('/') || relative.includes('//')) {
    throw new Error(`Frontend adapter has unsafe page path: ${pagePath}`)
  }
  return `../pages/${relative}`
}

export function loadFrontendApplicationAdapters(
  applicationId: string,
  modules: Record<string, unknown>,
): {
  pages: Record<string, FrontendPageLoader>
  errorBoundaries: readonly Component[]
  prepare: () => Promise<void>
  install: () => VoidFunction
  dispose: VoidFunction
  navigation: readonly ApplicationShellNavigationContribution[]
} {
  const descriptor = requireFrontendApplication(applicationId)
  const expectedModules = new Set(descriptor.adapterModules)
  const expectedContributions = new Map(
    descriptor.contributions
      .filter((contribution) => contribution.adapterModule)
      .map((contribution) => [contribution.adapterModule as string, contribution]),
  )
  const expectedErrorBoundaries = new Set(
    [...expectedContributions.values()]
      .map((contribution) => contribution.errorBoundary)
      .filter((name): name is string => Boolean(name)),
  )
  const discoveredModules = new Set<string>()
  const discoveredErrorBoundaries = new Set<string>()
  const pages: Record<string, FrontendPageLoader> = {}
  const errorBoundaries: Component[] = []
  const adapters: FrontendApplicationAdapter[] = []
  const navigation: ApplicationShellNavigationContribution[] = []
  const removeLocaleDomains: VoidFunction[] = []
  let disposed = false
  const dispose = () => {
    if (disposed) return
    disposed = true
    runCleanupStack(removeLocaleDomains)
  }

  try {
    for (const [modulePath, value] of Object.entries(modules).sort(([left], [right]) => (
      left.localeCompare(right)
    ))) {
      const canonicalPath = canonicalAdapterModulePath(modulePath)
      if (discoveredModules.has(canonicalPath)) {
        throw new Error(`Frontend adapter module is discovered twice: ${canonicalPath}`)
      }
      discoveredModules.add(canonicalPath)
      if (!expectedModules.has(canonicalPath)) {
        throw new Error(`Unregistered frontend adapter module for ${applicationId}: ${canonicalPath}`)
      }
      const contribution = expectedContributions.get(canonicalPath)
      if (!contribution) {
        throw new Error(`Frontend adapter module has no contribution identity: ${canonicalPath}`)
      }

      const adapter = adapterValue(modulePath, value)
      if (adapter.applicationId !== applicationId) {
        throw new Error(
          `Frontend adapter ${adapter.contributionId} targets ${adapter.applicationId}; `
            + `${applicationId} discovered it`,
        )
      }
      if (adapter.contributionId !== contribution.id) {
        throw new Error(
          `Frontend adapter path ${canonicalPath} belongs to ${contribution.id}; `
            + `${adapter.contributionId} cannot claim it`,
        )
      }

      const actualStyles = Object.keys(adapter.styleModules ?? {}).sort()
      const expectedStyles = [...contribution.styles].sort()
      if (actualStyles.join('\0') !== expectedStyles.join('\0')) {
        throw new Error(
          `Frontend adapter ${adapter.contributionId} styles do not match its manifest: `
            + `expected=${expectedStyles.join(', ')} actual=${actualStyles.join(', ')}`,
        )
      }
      if (Object.values(adapter.styleModules ?? {}).some((loader) => typeof loader !== 'function')) {
        throw new Error(`Frontend adapter ${adapter.contributionId} has a non-executable style loader`)
      }
      const actualLocales = Object.keys(adapter.localeDomains ?? {}).sort()
      const expectedLocales = [...contribution.locales].sort()
      if (actualLocales.join('\0') !== expectedLocales.join('\0')) {
        throw new Error(
          `Frontend adapter ${adapter.contributionId} locales do not match its manifest: `
            + `expected=${expectedLocales.join(', ')} actual=${actualLocales.join(', ')}`,
        )
      }
      if (contribution.draftContract && !isFrontendDraftAdapter(adapter.draftAdapter)) {
        throw new Error(`Frontend adapter ${adapter.contributionId} must provide an executable draft adapter`)
      }
      if (!contribution.draftContract && adapter.draftAdapter) {
        throw new Error(`Frontend adapter ${adapter.contributionId} has an undeclared draft adapter`)
      }
      if (!draftContractsMatch(adapter.draftAdapter?.contract, contribution.draftContract)) {
        throw new Error(`Frontend adapter ${adapter.contributionId} draft contract does not match`)
      }
      const actualNavigation = adapter.navigation ?? []
      if (navigationSignature(actualNavigation, adapter.contributionId)
        !== navigationSignature(contribution.navigation, contribution.id)) {
        throw new Error(`Frontend adapter ${adapter.contributionId} navigation does not match its manifest`)
      }
      if (actualNavigation.length > 0) {
        navigation.push({
          contributionId: adapter.contributionId,
          groups: actualNavigation,
        })
      }

      for (const [pagePath, loader] of Object.entries(adapter.pages ?? {})) {
        if (typeof loader !== 'function') {
          throw new Error(`Frontend adapter ${adapter.contributionId} has a non-executable page loader`)
        }
        const canonicalPath = canonicalPagePath(pagePath, contribution.pageRoots)
        const component = canonicalPath.slice('../pages/'.length, -'.vue'.length)
        const owner = assertFrontendComponent(applicationId, component)
        if (!owner.contribution || owner.contributionId !== adapter.contributionId) {
          throw new Error(
            `Frontend adapter ${adapter.contributionId} cannot provide ${component}; `
              + `registered contribution=${owner.contributionId ?? 'base'}`,
          )
        }
        if (pages[canonicalPath]) {
          throw new Error(`Frontend adapter page is claimed twice: ${canonicalPath}`)
        }
        pages[canonicalPath] = loader
      }
      for (const [domain, loaders] of Object.entries(adapter.localeDomains ?? {})) {
        removeLocaleDomains.push(registerFrontendLocaleDomain(domain, loaders))
      }
      if (adapter.errorBoundary) {
        const { name, component } = adapter.errorBoundary
        if (name !== contribution.errorBoundary || !expectedErrorBoundaries.has(name)) {
          throw new Error(
            `Frontend adapter ${adapter.contributionId} cannot provide error boundary: ${name}`,
          )
        }
        if (discoveredErrorBoundaries.has(name)) {
          throw new Error(`Frontend error boundary is provided twice: ${name}`)
        }
        discoveredErrorBoundaries.add(name)
        errorBoundaries.push(component)
      } else if (contribution.errorBoundary) {
        throw new Error(
          `Frontend adapter ${adapter.contributionId} must provide ${contribution.errorBoundary}`,
        )
      }
      adapters.push(adapter)
    }
  } catch (error) {
    dispose()
    throw error
  }

  const missingModules = [...expectedModules].filter((modulePath) => !discoveredModules.has(modulePath))
  if (missingModules.length > 0) {
    dispose()
    throw new Error(
      `Frontend application ${applicationId} is missing adapter modules: ${missingModules.join(', ')}`,
    )
  }
  const missingErrorBoundaries = [...expectedErrorBoundaries]
    .filter((name) => !discoveredErrorBoundaries.has(name))
  if (missingErrorBoundaries.length > 0) {
    dispose()
    throw new Error(
      `Frontend application ${applicationId} is missing error boundaries: `
        + missingErrorBoundaries.join(', '),
    )
  }

  for (const contribution of expectedContributions.values()) {
    for (const component of contribution.budget?.representativeComponents ?? []) {
      const path = `../pages/${component}.vue`
      if (!pages[path]) {
        dispose()
        throw new Error(
          `Frontend adapter ${contribution.id} does not provide representative page ${component}`,
        )
      }
    }
  }

  return {
    pages,
    errorBoundaries,
    navigation: Object.freeze(navigation.map((item) => Object.freeze({
      contributionId: item.contributionId,
      groups: Object.freeze(item.groups.map((group) => Object.freeze({
        ...group,
        items: Object.freeze(group.items.map((entry) => Object.freeze({ ...entry }))),
      }))),
    }))),
    async prepare() {
      await Promise.all(adapters.flatMap((adapter) => (
        Object.values(adapter.styleModules ?? {}).map((loader) => loader())
      )))
    },
    install() {
      const cleanup: VoidFunction[] = []
      try {
        for (const adapter of adapters) {
          if (adapter.draftAdapter) {
            cleanup.push(installFrontendDraftAdapter(
              applicationId,
              adapter.contributionId,
              adapter.draftAdapter,
            ))
          }
          const result = adapter.install?.()
          if (typeof result === 'function') cleanup.push(result)
        }
      } catch (error) {
        runCleanupStack(cleanup)
        throw error
      }
      let installed = true
      return () => {
        if (!installed) return
        installed = false
        runCleanupStack(cleanup)
      }
    },
    dispose,
  }
}
