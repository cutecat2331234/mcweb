import type {
  FrontendApplicationDescriptor,
  FrontendApplicationRegistryData,
  FrontendComponentClaim as ComponentClaim,
  FrontendRouteMatch,
} from './frontendApplicationTypes.ts'

export const FRONTEND_APPLICATION_HEADER = 'X-McWeb-Application'

export function routePatternExpression(pattern: string): RegExp {
  let expression = ''
  for (let index = 0; index < pattern.length;) {
    if (pattern.slice(index, index + 2) === '**') {
      expression += '.*'
      index += 2
    } else if (pattern[index] === '*') {
      expression += '[^/]*'
      index += 1
    } else {
      expression += pattern[index].replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
      index += 1
    }
  }
  return new RegExp(`^${expression}$`)
}

function freezeRegistryValue(value: unknown): void {
  if (value === null || typeof value !== 'object') return
  for (const child of Object.values(value)) freezeRegistryValue(child)
  Object.freeze(value)
}

// This factory only consumes a compiler-validated, serializable snapshot. Keep
// manifest parsing and cross-manifest validation outside the browser graph.
export function createFrontendApplicationRegistry(data: FrontendApplicationRegistryData) {
  freezeRegistryValue(data)
  const frontendApplications = data.applications
  const frontendRouteRules = data.routeRules
  const frozenApplications = new Map(frontendApplications.map((application) => [application.id, application]))
  const componentClaims = data.componentClaims
  const launchers = data.launchers
  const compiledRouteRules = frontendRouteRules.map((rule) => ({
    rule,
    matcher: routePatternExpression(rule.pattern),
  }))

  function frontendApplication(id: string): FrontendApplicationDescriptor | null {
    return frozenApplications.get(id) ?? null
  }

  function requireFrontendApplication(id: string): FrontendApplicationDescriptor {
    const application = frontendApplication(id)
    if (!application) throw new Error(`Unknown frontend application: ${id}`)
    return application
  }

  function frontendLauncherApplication(
    path = '/app',
  ): FrontendApplicationDescriptor | null {
    const launcher = launchers.find((candidate) => candidate.path === path)
    return launcher ? requireFrontendApplication(launcher.applicationId) : null
  }

  function resolveFrontendRoute(
    path: string,
    method = 'GET',
  ): FrontendRouteMatch | null {
    if (!path.startsWith('/') || path.startsWith('//') || path.includes('\\')) return null
    const normalizedMethod = method.toUpperCase()
    const candidate = compiledRouteRules.find(({ rule, matcher }) => (
      rule.methods.includes(normalizedMethod) && matcher.test(path)
    ))
    if (!candidate) return null
    return {
      application: candidate.rule.applicationId
        ? requireFrontendApplication(candidate.rule.applicationId)
        : null,
      rule: candidate.rule,
    }
  }

  function frontendComponentOwner(component: string): Readonly<ComponentClaim> | null {
    if (!component || component.startsWith('/') || component.endsWith('/')
      || component.includes('\\') || component.includes('..')) return null
    return componentClaims.find((claim) => (
      claim.exact ? component === claim.prefix : component.startsWith(claim.prefix)
    )) ?? null
  }

  function assertFrontendComponent(
    applicationId: string,
    component: string,
    productOwner?: string,
  ): Readonly<ComponentClaim> {
    const application = requireFrontendApplication(applicationId)
    const owner = frontendComponentOwner(component)
    if (!owner) throw new Error(`Component ${component} has no frontend application owner`)
    if (productOwner && owner.productOwner !== productOwner) {
      throw new Error(
        `Route owner ${productOwner} cannot resolve ${component}; component owner=${owner.productOwner}`,
      )
    }
    if (owner.runtimeApplicationId === application.id) return owner
    if (application.projections.some((projection) => (
      component.startsWith(projection.prefix)
      && projection.ownerApplication === owner.runtimeApplicationId
    ))) return owner
    throw new Error(
      `Frontend application ${application.id} cannot resolve ${component}; `
        + `owner=${owner.productOwner} runtime=${owner.runtimeApplicationId}`,
    )
  }

  function frontendApplicationRequestHeaders(
    applicationId: string,
  ): Record<string, string> {
    requireFrontendApplication(applicationId)
    return { [FRONTEND_APPLICATION_HEADER]: applicationId }
  }

  function documentFrontendApplicationId(): string {
    const id = document.documentElement.dataset.mcwebApplication
    if (!id) throw new Error('Document has no frontend application identity')
    requireFrontendApplication(id)
    return id
  }

  function frontendRouteSourceAllowed(
    routeMatch: FrontendRouteMatch,
    sourceApplicationId: string,
  ): boolean {
    const source = frontendApplication(sourceApplicationId)
    if (!source) return false
    return routeMatch.rule.allowedSourceApplications.includes(source.id)
      || routeMatch.rule.allowedSourceCapabilities
        .some((capability) => source.capabilities.includes(capability))
  }

  return Object.freeze({
    frontendApplications,
    frontendRouteRules,
    frontendApplication,
    requireFrontendApplication,
    frontendLauncherApplication,
    resolveFrontendRoute,
    frontendComponentOwner,
    assertFrontendComponent,
    frontendApplicationRequestHeaders,
    documentFrontendApplicationId,
    frontendRouteSourceAllowed,
  })
}
