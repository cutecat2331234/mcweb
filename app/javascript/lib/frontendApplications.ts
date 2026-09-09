import compiledRegistry from 'virtual:mcweb/frontend-applications'
import { createFrontendApplicationRegistry } from './frontendApplicationRegistry.ts'

export type * from './frontendApplicationTypes.ts'
export { FRONTEND_APPLICATION_HEADER } from './frontendApplicationRegistry.ts'

// Vite emits only immutable descriptors. Full schema, contribution ownership,
// overlap and recovery validation is performed by the build-only compiler.
export const {
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
} = createFrontendApplicationRegistry(compiledRegistry)
