import type { ApplicationShellNavigationGroup } from './applicationShell'

export type FrontendRouteKind =
  | 'inertia_page'
  | 'application_action'
  | 'document'
  | 'download'
  | 'api'
  | 'shared_action'

export type FrontendRuntimeKind = 'inertia' | 'inertia_document' | 'astro_document'

export type FrontendRouteRule = Readonly<{
  applicationId: string | null
  productOwner: string
  kind: FrontendRouteKind
  methods: readonly string[]
  pattern: string
  priority: number
  allowedSourceApplications: readonly string[]
  allowedSourceCapabilities: readonly string[]
  safeGetPath: string | null
  source: string
  contribution: boolean
  contributionId: string | null
}>

export type FrontendProjection = Readonly<{
  prefix: string
  ownerApplication: string
}>

export type FrontendApplicationBudget = Readonly<{
  representativePaths: readonly string[]
  representativeComponents: readonly string[]
  representativeEntries: readonly string[]
  conditionalInitialEntries: readonly string[]
  maxInitialJavascriptBytes: number
  maxInitialStylesheetBytes: number | null
}>

export type FrontendApplicationLauncher = Readonly<{
  path: string
  priority: number
}>

export type FrontendRendererContract = Readonly<{
  adapter: string
  contributionId: string | null
  productOwner: string
  runtimeOwner: string
  previewKind: 'inertia_canvas' | 'document_frame'
  manifestPath: string | null
}>

export type FrontendDraftContract = Readonly<{
  capability: string
  keyNamespace: string
  version: number
  userScoped: true
  resourceScoped: true
  offlineRecovery: true
  clearOnSubmit: true
}>

export type FrontendApplicationContribution = Readonly<{
  id: string
  productOwner: string
  runtimeOwner: string
  adapterModule: string | null
  pageRoots: readonly string[]
  styles: readonly string[]
  locales: readonly string[]
  errorBoundary: string | null
  draftContract: FrontendDraftContract | null
  navigation: readonly ApplicationShellNavigationGroup[]
  accessories: readonly string[]
  budget: FrontendApplicationBudget | null
}>

export type FrontendApplicationDescriptor = Readonly<{
  id: string
  productOwner: string
  runtimeOwner: string
  runtimeKind: FrontendRuntimeKind
  entrypoint: string
  landingPath: string
  componentPrefixes: readonly string[]
  componentNames: readonly string[]
  allowDescendantContributions: boolean
  projections: readonly FrontendProjection[]
  shellAdapter: string
  uiAdapter: string
  styles: readonly string[]
  locales: readonly string[]
  errorBoundaries: readonly string[]
  capabilities: readonly string[]
  budget: FrontendApplicationBudget
  launcher: FrontendApplicationLauncher | null
  rendererAdapters: readonly string[]
  renderer: FrontendRendererContract | null
  adapterModules: readonly string[]
  contributions: readonly FrontendApplicationContribution[]
}>

export type FrontendRouteMatch = Readonly<{
  application: FrontendApplicationDescriptor | null
  rule: FrontendRouteRule
}>

export type FrontendComponentClaim = Readonly<{
  prefix: string
  exact: boolean
  productOwner: string
  runtimeApplicationId: string
  contributionId: string | null
  source: string
  contribution: boolean
}>

// Serializable output of the build-only manifest compiler. Runtime consumers
// must use the generated virtual module, never load raw manifests themselves.
export type FrontendApplicationRegistryData = Readonly<{
  applications: readonly FrontendApplicationDescriptor[]
  routeRules: readonly FrontendRouteRule[]
  componentClaims: readonly FrontendComponentClaim[]
  launchers: readonly Readonly<{ path: string; applicationId: string }>[]
}>
