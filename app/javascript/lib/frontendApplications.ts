import sharedRoutesManifest from '../../../config/frontend_applications/shared_routes.json'
import type { ApplicationShellNavigationGroup } from '@/lib/applicationShell'

export const FRONTEND_APPLICATION_HEADER = 'X-McWeb-Application'

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

type JsonObject = Record<string, unknown>

type MutableApplication = {
  id: string
  productOwner: string
  runtimeOwner: string
  runtimeKind: FrontendRuntimeKind
  entrypoint: string
  landingPath: string
  componentPrefixes: string[]
  componentNames: string[]
  allowDescendantContributions: boolean
  projections: FrontendProjection[]
  shellAdapter: string
  uiAdapter: string
  styles: string[]
  locales: string[]
  errorBoundaries: string[]
  capabilities: string[]
  budget: FrontendApplicationBudget
  launcher: FrontendApplicationLauncher | null
  rendererAdapters: string[]
  renderer: FrontendRendererContract | null
  adapterModules: string[]
  contributions: FrontendApplicationContribution[]
  routeRules: FrontendRouteRule[]
  source: string
}

type ComponentClaim = {
  prefix: string
  exact: boolean
  productOwner: string
  runtimeApplicationId: string
  contributionId: string | null
  source: string
  contribution: boolean
}

const ROUTE_KINDS = new Set<FrontendRouteKind>([
  'inertia_page',
  'application_action',
  'document',
  'download',
  'api',
  'shared_action',
])
const RUNTIME_KINDS = new Set<FrontendRuntimeKind>([
  'inertia',
  'inertia_document',
  'astro_document',
])
const HTTP_METHODS = new Set(['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE'])
const IDENTIFIER = /^[a-z][a-z0-9_]*$/
const OWNER_IDENTIFIER = /^[a-z][a-z0-9_-]*$/
const COMPONENT_PREFIX = /^[A-Z][A-Za-z0-9]*(?:\/[A-Z][A-Za-z0-9]*)*\/$/
const SHARED_ADAPTER_STYLES = new Set(['tokens', 'shell_foundation', 'app_shell', 'arco_admin'])
const SHARED_ADAPTER_LOCALES = new Set(['core'])

const baseManifestModules = import.meta.glob(
  '../../../config/frontend_applications/base/*.json',
  { eager: true, import: 'default' },
) as Record<string, unknown>

const contributionManifestModules = import.meta.glob(
  '../../../config/frontend_applications/contributions/*.json',
  { eager: true, import: 'default' },
) as Record<string, unknown>

function manifestError(source: string, message: string): never {
  throw new Error(`Invalid frontend application manifest ${source}: ${message}`)
}

function objectValue(value: unknown, source: string): JsonObject {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return manifestError(source, 'expected an object')
  }
  return value as JsonObject
}

function assertExactKeys(
  value: JsonObject,
  allowed: readonly string[],
  source: string,
  required: readonly string[] = allowed,
): void {
  const missing = required.filter((key) => !Object.hasOwn(value, key))
  const unknown = Object.keys(value).filter((key) => !allowed.includes(key))
  if (missing.length > 0 || unknown.length > 0) {
    manifestError(
      source,
      `manifest keys mismatch missing=${missing.join(', ')} unknown=${unknown.join(', ')}`,
    )
  }
}

function stringValue(value: unknown, source: string, field: string): string {
  if (typeof value !== 'string' || value.length === 0) {
    return manifestError(source, `${field} must be a non-empty string`)
  }
  return value
}

function identifierValue(value: unknown, source: string, field: string): string {
  const candidate = stringValue(value, source, field)
  if (!IDENTIFIER.test(candidate)) manifestError(source, `invalid ${field} ${JSON.stringify(candidate)}`)
  return candidate
}

function ownerValue(value: unknown, source: string, field: string): string {
  const candidate = stringValue(value, source, field)
  if (!OWNER_IDENTIFIER.test(candidate)) {
    manifestError(source, `invalid ${field} ${JSON.stringify(candidate)}`)
  }
  return candidate
}

function adapterNameValue(value: unknown, source: string, field: string): string {
  const candidate = stringValue(value, source, field)
  if (!/^[a-z][a-z0-9_.-]*$/.test(candidate)) {
    manifestError(source, `invalid ${field} ${JSON.stringify(candidate)}`)
  }
  return candidate
}

function localeKeyValue(value: unknown, source: string, field: string): string {
  const candidate = stringValue(value, source, field)
  if (!/^[a-z][A-Za-z0-9_-]*(?:\.[a-z][A-Za-z0-9_-]*)*$/.test(candidate)) {
    manifestError(source, `invalid ${field} ${JSON.stringify(candidate)}`)
  }
  return candidate
}

function entrypointValue(value: unknown, source: string, field = 'entrypoint'): string {
  const candidate = stringValue(value, source, field)
  if (!/^[a-z][a-z0-9-]*$/.test(candidate)) {
    manifestError(source, `invalid ${field} ${JSON.stringify(candidate)}`)
  }
  return candidate
}

function adapterModuleValue(value: unknown, source: string, applicationId: string): string {
  const candidate = stringValue(value, source, 'adapter_module').replaceAll('\\', '/')
  const applicationRoot = `app/javascript/frontend-application-adapters/${applicationId}/`
  const valid = candidate.startsWith(applicationRoot)
    && /^app\/javascript\/frontend-application-adapters\/[a-z0-9_./-]+\.ts$/.test(candidate)
    && !candidate.includes('..')
    && !candidate.includes('//')
  if (!valid) manifestError(source, `invalid adapter_module ${JSON.stringify(candidate)}`)
  return candidate
}

function repositoryPathValue(value: unknown, source: string, field: string): string {
  const candidate = stringValue(value, source, field).replaceAll('\\', '/')
  const segments = candidate.split('/')
  if (candidate.startsWith('/') || candidate.includes('//') || candidate.includes(':')
    || segments.some((segment) => segment === '' || segment === '.' || segment === '..')
    || /[\u0000-\u001f\u007f]/.test(candidate)) {
    manifestError(source, `invalid ${field} ${JSON.stringify(candidate)}`)
  }
  return candidate
}

function arrayValue(value: unknown, source: string, field: string): unknown[] {
  if (!Array.isArray(value)) manifestError(source, `${field} must be an array`)
  return value
}

function uniqueStrings(
  value: unknown,
  source: string,
  field: string,
  { allowEmpty = true, pattern }: { allowEmpty?: boolean; pattern?: RegExp } = {},
): string[] {
  const values = arrayValue(value, source, field).map((item) => {
    const candidate = stringValue(item, source, field)
    if (pattern && !pattern.test(candidate)) {
      manifestError(source, `invalid ${field} value ${JSON.stringify(candidate)}`)
    }
    return candidate
  })
  if (!allowEmpty && values.length === 0) manifestError(source, `${field} must not be empty`)
  if (new Set(values).size !== values.length) manifestError(source, `${field} contains duplicates`)
  return values
}

function pathValue(
  value: unknown,
  source: string,
  field: string,
  { pattern = false }: { pattern?: boolean } = {},
): string {
  const candidate = stringValue(value, source, field)
  let hasDotSegment = false
  try {
    hasDotSegment = candidate.split('/').some((segment) => {
      const decoded = decodeURIComponent(segment)
      return decoded === '.' || decoded === '..'
        || /[\\/\u0000-\u001f\u007f]/.test(decoded)
    })
  } catch {
    hasDotSegment = true
  }
  const unsafe = !candidate.startsWith('/')
    || candidate.startsWith('//')
    || candidate.includes('\\')
    || /[\u0000-\u001f\u007f]/.test(candidate)
    || candidate.includes('?')
    || candidate.includes('#')
    || (!pattern && candidate.includes('*'))
    || (pattern && candidate.includes('***'))
    || hasDotSegment
  if (unsafe) manifestError(source, `invalid ${field} ${JSON.stringify(candidate)}`)
  return candidate
}

function positiveInteger(value: unknown, source: string, field: string): number {
  if (!Number.isInteger(value) || (value as number) <= 0) {
    manifestError(source, `${field} must be a positive integer`)
  }
  return value as number
}

function buildProjection(value: unknown, source: string): FrontendProjection {
  const projection = objectValue(value, source)
  assertExactKeys(projection, ['prefix', 'owner_application'], source)
  const prefix = stringValue(projection.prefix, source, 'prefix')
  if (!COMPONENT_PREFIX.test(prefix)) manifestError(source, `invalid projection prefix ${prefix}`)
  return {
    prefix,
    ownerApplication: identifierValue(
      projection.owner_application,
      source,
      'owner_application',
    ),
  }
}

function buildNavigation(
  value: unknown,
  source: string,
): ApplicationShellNavigationGroup[] {
  return arrayValue(value, source, 'navigation').map((rawGroup, groupIndex) => {
    const groupSource = `${source}#navigation[${groupIndex}]`
    const group = objectValue(rawGroup, groupSource)
    assertExactKeys(group, ['id', 'label_key', 'items'], groupSource)
    const items = arrayValue(group.items, groupSource, 'items').map((rawItem, itemIndex) => {
      const itemSource = `${groupSource}#items[${itemIndex}]`
      const item = objectValue(rawItem, itemSource)
      assertExactKeys(
        item,
        ['href', 'label_key', 'badge_prop', 'visibility_prop', 'requires_authentication'],
        itemSource,
        ['href', 'label_key'],
      )
      if (item.requires_authentication !== undefined
        && typeof item.requires_authentication !== 'boolean') {
        manifestError(itemSource, 'requires_authentication must be a boolean')
      }
      return {
        href: pathValue(item.href, itemSource, 'href'),
        labelKey: localeKeyValue(item.label_key, itemSource, 'label_key'),
        ...(item.badge_prop === undefined ? {} : {
          badgeProp: adapterNameValue(item.badge_prop, itemSource, 'badge_prop'),
        }),
        ...(item.visibility_prop === undefined ? {} : {
          visibilityProp: adapterNameValue(
            item.visibility_prop,
            itemSource,
            'visibility_prop',
          ),
        }),
        ...(item.requires_authentication === undefined ? {} : {
          requiresAuthentication: item.requires_authentication,
        }),
      }
    })
    if (items.length === 0) manifestError(groupSource, 'navigation group items must not be empty')
    return {
      id: adapterNameValue(group.id, groupSource, 'id'),
      labelKey: localeKeyValue(group.label_key, groupSource, 'label_key'),
      items,
    }
  })
}

function pageRootsValue(value: unknown, source: string): string[] {
  const roots = uniqueStrings(
    value ?? ['app/javascript/pages'],
    source,
    'page_roots',
    { pattern: /^(?:[a-z][a-z0-9_-]*\/)*app\/javascript\/pages$/ },
  )
  if (roots.length === 0) manifestError(source, 'page_roots must not be empty')
  return roots
}

function buildBudget(value: unknown, source: string): FrontendApplicationBudget {
  const budget = objectValue(value, `${source}#budget`)
  assertExactKeys(
    budget,
    [
      'representative_paths',
      'representative_components',
      'representative_entries',
      'max_initial_javascript_bytes',
      'max_initial_stylesheet_bytes',
    ],
    `${source}#budget`,
    [
      'representative_paths',
      'max_initial_javascript_bytes',
    ],
  )
  const representativePaths = arrayValue(
    budget.representative_paths,
    `${source}#budget`,
    'representative_paths',
  ).map((path) => pathValue(path, `${source}#budget`, 'representative_paths'))
  if (representativePaths.length === 0) {
    manifestError(`${source}#budget`, 'representative_paths must not be empty')
  }
  const hasComponents = budget.representative_components !== undefined
  const hasEntries = budget.representative_entries !== undefined
  if (hasComponents === hasEntries) {
    manifestError(`${source}#budget`, 'declare exactly one representative component or entry list')
  }
  const representativeComponents = hasComponents
    ? uniqueStrings(
      budget.representative_components,
      `${source}#budget`,
      'representative_components',
      { allowEmpty: false, pattern: /^[A-Z][A-Za-z0-9]*(?:\/[A-Z][A-Za-z0-9]*)*$/ },
    )
    : []
  const representativeEntries = hasEntries
    ? arrayValue(budget.representative_entries, `${source}#budget`, 'representative_entries')
      .map((entry) => repositoryPathValue(entry, `${source}#budget`, 'representative_entries'))
    : []
  if (new Set(representativeEntries).size !== representativeEntries.length) {
    manifestError(`${source}#budget`, 'representative_entries contains duplicates')
  }
  if (hasEntries && representativeEntries.length === 0) {
    manifestError(`${source}#budget`, 'representative_entries must not be empty')
  }
  const representativeResources = hasComponents
    ? representativeComponents
    : representativeEntries
  if (representativeResources.length !== representativePaths.length) {
    manifestError(`${source}#budget`, 'representative paths and resources must have equal length')
  }

  return {
    representativePaths,
    representativeComponents,
    representativeEntries,
    maxInitialJavascriptBytes: positiveInteger(
      budget.max_initial_javascript_bytes,
      `${source}#budget`,
      'max_initial_javascript_bytes',
    ),
    maxInitialStylesheetBytes: budget.max_initial_stylesheet_bytes === undefined
      ? null
      : positiveInteger(
        budget.max_initial_stylesheet_bytes,
        `${source}#budget`,
        'max_initial_stylesheet_bytes',
      ),
  }
}

function buildLauncher(value: unknown, source: string): FrontendApplicationLauncher {
  const launcher = objectValue(value, `${source}#launcher`)
  assertExactKeys(launcher, ['path', 'priority'], `${source}#launcher`)
  if (!Number.isInteger(launcher.priority) || (launcher.priority as number) < 0) {
    manifestError(`${source}#launcher`, 'priority must be a non-negative integer')
  }
  return {
    path: pathValue(launcher.path, `${source}#launcher`, 'path'),
    priority: launcher.priority as number,
  }
}

function buildDraftContract(value: unknown, source: string): FrontendDraftContract {
  const contract = objectValue(value, `${source}#draft_contract`)
  const expectedKeys = [
    'capability',
    'key_namespace',
    'version',
    'user_scoped',
    'resource_scoped',
    'offline_recovery',
    'clear_on_submit',
  ]
  assertExactKeys(contract, expectedKeys, `${source}#draft_contract`)
  if (!Number.isInteger(contract.version) || (contract.version as number) <= 0
    || contract.user_scoped !== true
    || contract.resource_scoped !== true
    || contract.offline_recovery !== true
    || contract.clear_on_submit !== true) {
    manifestError(source, 'draft_contract requires a positive version and all isolation flags')
  }
  return {
    capability: identifierValue(contract.capability, source, 'draft_contract.capability'),
    keyNamespace: identifierValue(
      contract.key_namespace,
      source,
      'draft_contract.key_namespace',
    ),
    version: contract.version as number,
    userScoped: true,
    resourceScoped: true,
    offlineRecovery: true,
    clearOnSubmit: true,
  }
}

function mergeApplicationBudget(
  target: FrontendApplicationBudget,
  contribution: FrontendApplicationBudget,
): FrontendApplicationBudget {
  const stylesheetLimits = [
    target.maxInitialStylesheetBytes,
    contribution.maxInitialStylesheetBytes,
  ].filter((value): value is number => value !== null)
  return {
    representativePaths: [...target.representativePaths, ...contribution.representativePaths],
    representativeComponents: [
      ...target.representativeComponents,
      ...contribution.representativeComponents,
    ],
    representativeEntries: [
      ...target.representativeEntries,
      ...contribution.representativeEntries,
    ],
    maxInitialJavascriptBytes: Math.max(
      target.maxInitialJavascriptBytes,
      contribution.maxInitialJavascriptBytes,
    ),
    maxInitialStylesheetBytes: stylesheetLimits.length > 0
      ? Math.max(...stylesheetLimits)
      : null,
  }
}

function buildRouteRule(
  value: unknown,
  source: string,
  applicationId: string | null,
  productOwner: string,
  contribution = false,
  contributionId: string | null = null,
): FrontendRouteRule {
  const raw = objectValue(value, source)
  assertExactKeys(
    raw,
    [
      'kind',
      'methods',
      'pattern',
      'priority',
      'allowed_source_applications',
      'allowed_source_capabilities',
      'safe_get_path',
    ],
    source,
    ['kind', 'methods', 'pattern', 'priority'],
  )
  const kind = stringValue(raw.kind, source, 'kind') as FrontendRouteKind
  if (!ROUTE_KINDS.has(kind)) manifestError(source, `unsupported route kind ${kind}`)

  const methods = uniqueStrings(raw.methods, source, 'methods')
  if (methods.length === 0 || methods.some((method) => !HTTP_METHODS.has(method))) {
    manifestError(source, `invalid HTTP methods ${methods.join(', ')}`)
  }
  if (kind === 'inertia_page' && methods.some((method) => method !== 'GET' && method !== 'HEAD')) {
    manifestError(source, 'inertia_page permits only GET/HEAD')
  }
  if (kind === 'document' && methods.some((method) => method !== 'GET' && method !== 'HEAD')) {
    manifestError(source, 'document permits only GET/HEAD')
  }
  if ((kind === 'application_action' || kind === 'shared_action')
    && methods.some((method) => method === 'GET' || method === 'HEAD')) {
    manifestError(source, `${kind} must be non-GET`)
  }

  if (!Number.isInteger(raw.priority) || (raw.priority as number) < 0) {
    manifestError(source, 'priority must be a non-negative integer')
  }

  const allowedSourceApplications = uniqueStrings(
    raw.allowed_source_applications ?? [],
    source,
    'allowed_source_applications',
    { pattern: IDENTIFIER },
  )
  const allowedSourceCapabilities = uniqueStrings(
    raw.allowed_source_capabilities ?? [],
    source,
    'allowed_source_capabilities',
  )
  const safeGetPath = raw.safe_get_path === undefined
    ? null
    : pathValue(raw.safe_get_path, source, 'safe_get_path')
  if (kind === 'shared_action'
    && (allowedSourceApplications.length === 0 && allowedSourceCapabilities.length === 0
      || !safeGetPath)) {
    manifestError(source, 'shared_action requires allowed source ids/capabilities and safe_get_path')
  }
  if (kind !== 'shared_action'
    && (allowedSourceApplications.length > 0 || allowedSourceCapabilities.length > 0 || safeGetPath)) {
    manifestError(source, 'allowed sources and safe_get_path apply only to shared_action')
  }

  return {
    applicationId,
    productOwner,
    kind,
    methods,
    pattern: pathValue(raw.pattern, source, 'pattern', { pattern: true }),
    priority: raw.priority as number,
    allowedSourceApplications,
    allowedSourceCapabilities,
    safeGetPath,
    source,
    contribution,
    contributionId,
  }
}

function buildApplication(
  value: unknown,
  source: string,
  contribution = false,
  contributionId: string | null = null,
): MutableApplication {
  const raw = objectValue(value, source)
  const requiredKeys = [
    'schema_version',
    'id',
    'product_owner',
    'runtime_owner',
    'runtime_kind',
    'entrypoint',
    'landing_path',
    'component_prefixes',
    'component_names',
    'projections',
    'shell_adapter',
    'ui_adapter',
    'styles',
    'locales',
    'error_boundary',
    'budget',
    'routes',
  ]
  assertExactKeys(
    raw,
    [
      ...requiredKeys,
      'allow_descendant_contributions',
      'capabilities',
      'renderer_adapter',
      'renderer_preview_kind',
      'renderer_manifest_path',
      'launcher',
    ],
    source,
    requiredKeys,
  )
  if (raw.schema_version !== 1) manifestError(source, 'schema_version must be 1')
  const id = identifierValue(raw.id, source, 'id')
  const runtimeKind = stringValue(raw.runtime_kind, source, 'runtime_kind') as FrontendRuntimeKind
  if (!RUNTIME_KINDS.has(runtimeKind)) {
    manifestError(source, `unsupported runtime_kind ${runtimeKind}`)
  }
  const productOwner = ownerValue(raw.product_owner, source, 'product_owner')
  const runtimeOwner = ownerValue(raw.runtime_owner, source, 'runtime_owner')
  const componentPrefixes = uniqueStrings(
    raw.component_prefixes,
    source,
    'component_prefixes',
    { allowEmpty: id === 'website_preview', pattern: COMPONENT_PREFIX },
  )
  const componentNames = uniqueStrings(
    raw.component_names,
    source,
    'component_names',
    { pattern: /^[A-Z][A-Za-z0-9]*(?:\/[A-Z][A-Za-z0-9]*)*$/ },
  )
  const routeRules = arrayValue(raw.routes, source, 'routes').map((rule, index) => (
    buildRouteRule(
      rule,
      `${source}#routes[${index}]`,
      id,
      productOwner,
      contribution,
      contributionId,
    )
  ))
  if (routeRules.length === 0) manifestError(source, 'routes must not be empty')

  const rendererAdapters = raw.renderer_adapter === undefined
    ? []
    : [adapterNameValue(raw.renderer_adapter, source, 'renderer_adapter')]
  if (runtimeKind === 'inertia' && rendererAdapters.length > 0) {
    manifestError(source, 'Inertia applications cannot declare a document renderer')
  }
  if (runtimeKind !== 'inertia' && rendererAdapters.length !== 1) {
    manifestError(source, 'document applications require exactly one renderer_adapter')
  }
  const rendererPreviewKind = raw.renderer_preview_kind === undefined
    ? null
    : stringValue(raw.renderer_preview_kind, source, 'renderer_preview_kind')
  if (rendererAdapters.length > 0
    && rendererPreviewKind !== 'inertia_canvas'
    && rendererPreviewKind !== 'document_frame') {
    manifestError(source, 'document renderer requires a supported renderer_preview_kind')
  }
  const rendererManifestPath = raw.renderer_manifest_path === undefined
    ? null
    : repositoryPathValue(raw.renderer_manifest_path, source, 'renderer_manifest_path')
  if (runtimeKind === 'astro_document' && !rendererManifestPath) {
    manifestError(source, 'Astro document renderer requires renderer_manifest_path')
  }
  if (runtimeKind !== 'astro_document' && rendererManifestPath) {
    manifestError(source, 'renderer_manifest_path applies only to Astro document renderers')
  }

  return {
    id,
    productOwner,
    runtimeOwner,
    runtimeKind,
    entrypoint: entrypointValue(raw.entrypoint, source),
    landingPath: pathValue(raw.landing_path, source, 'landing_path'),
    componentPrefixes,
    componentNames,
    allowDescendantContributions: raw.allow_descendant_contributions === true,
    projections: arrayValue(raw.projections, source, 'projections')
      .map((projection, index) => buildProjection(projection, `${source}#projections[${index}]`)),
    shellAdapter: adapterNameValue(raw.shell_adapter, source, 'shell_adapter'),
    uiAdapter: adapterNameValue(raw.ui_adapter, source, 'ui_adapter'),
    styles: uniqueStrings(raw.styles, source, 'styles', { allowEmpty: false }),
    locales: uniqueStrings(raw.locales, source, 'locales', { allowEmpty: false }),
    errorBoundaries: [adapterNameValue(raw.error_boundary, source, 'error_boundary')],
    capabilities: uniqueStrings(raw.capabilities ?? [], source, 'capabilities'),
    budget: buildBudget(raw.budget, source),
    launcher: raw.launcher === undefined ? null : buildLauncher(raw.launcher, source),
    rendererAdapters,
    renderer: rendererAdapters.length > 0 ? {
      adapter: rendererAdapters[0],
      contributionId,
      productOwner,
      runtimeOwner,
      previewKind: rendererPreviewKind as 'inertia_canvas' | 'document_frame',
      manifestPath: rendererManifestPath,
    } : null,
    adapterModules: [],
    contributions: [],
    routeRules,
    source,
  }
}

function routePatternExpression(pattern: string): RegExp {
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

const applications = new Map<string, MutableApplication>()
const routeRules: FrontendRouteRule[] = []
const componentClaims: ComponentClaim[] = []

for (const [source, manifest] of Object.entries(baseManifestModules).sort(([left], [right]) => (
  left.localeCompare(right)
))) {
  const application = buildApplication(manifest, source)
  if (applications.has(application.id)) manifestError(source, `duplicate application id ${application.id}`)
  applications.set(application.id, application)
  routeRules.push(...application.routeRules)
  componentClaims.push(...application.componentPrefixes.map((prefix) => ({
    prefix,
    exact: false,
    productOwner: application.productOwner,
    runtimeApplicationId: application.id,
    contributionId: null,
    source,
    contribution: false,
  })))
  componentClaims.push(...application.componentNames.map((name) => ({
    prefix: name,
    exact: true,
    productOwner: application.productOwner,
    runtimeApplicationId: application.id,
    contributionId: null,
    source,
    contribution: false,
  })))
}

const contributionEntries = Object.entries(contributionManifestModules)
  .sort(([left], [right]) => left.localeCompare(right))
  .map(([source, value]) => ({ source, raw: objectValue(value, source) }))
const contributionIds = new Map<string, string>()

for (const { source, raw } of contributionEntries) {
  if (raw.schema_version !== 1) manifestError(source, 'schema_version must be 1')
  const contributionId = stringValue(raw.contribution_id, source, 'contribution_id')
  if (!/^[a-z][a-z0-9_.-]*$/.test(contributionId)) {
    manifestError(source, `invalid contribution_id ${contributionId}`)
  }
  const firstSource = contributionIds.get(contributionId)
  if (firstSource) manifestError(source, `duplicate contribution_id first declared by ${firstSource}`)
  contributionIds.set(contributionId, source)
  ownerValue(raw.product_owner, source, 'product_owner')
  ownerValue(raw.runtime_owner, source, 'runtime_owner')
  if ((raw.creates_application === undefined) === (raw.extends_application === undefined)) {
    manifestError(source, 'declare exactly one of creates_application or extends_application')
  }
}

for (const { source, raw } of contributionEntries) {
  if (raw.creates_application === undefined) continue
  assertExactKeys(
    raw,
    [
      'schema_version',
      'contribution_id',
      'product_owner',
      'runtime_owner',
      'creates_application',
      'adapter_module',
      'page_roots',
      'draft_contract',
    ],
    source,
    [
      'schema_version',
      'contribution_id',
      'product_owner',
      'runtime_owner',
      'creates_application',
    ],
  )
  const contributionId = stringValue(raw.contribution_id, source, 'contribution_id')
  const created = {
    ...objectValue(raw.creates_application, `${source}#creates_application`),
    product_owner: raw.product_owner,
    runtime_owner: raw.runtime_owner,
  }
  const application = buildApplication(created, source, true, contributionId)
  if (applications.has(application.id)) manifestError(source, `duplicate application id ${application.id}`)
  if (application.runtimeKind === 'inertia' && raw.adapter_module === undefined) {
    manifestError(source, 'created Inertia applications require adapter_module')
  }
  const adapterModule = raw.adapter_module === undefined
    ? null
    : adapterModuleValue(raw.adapter_module, source, application.id)
  if (raw.adapter_module !== undefined) {
    application.adapterModules.push(adapterModule as string)
  }
  const pageRoots = pageRootsValue(raw.page_roots, source)
  application.contributions.push({
    id: contributionId,
    productOwner: application.productOwner,
    runtimeOwner: application.runtimeOwner,
    adapterModule,
    pageRoots,
    styles: application.styles.filter((style) => !SHARED_ADAPTER_STYLES.has(style)),
    locales: application.locales.filter((locale) => !SHARED_ADAPTER_LOCALES.has(locale)),
    errorBoundary: application.errorBoundaries[0] ?? null,
    draftContract: raw.draft_contract === undefined
      ? null
      : buildDraftContract(raw.draft_contract, source),
    navigation: [],
    budget: application.budget,
  })
  applications.set(application.id, application)
  routeRules.push(...application.routeRules)
  componentClaims.push(...application.componentPrefixes.map((prefix) => ({
    prefix,
    exact: false,
    productOwner: application.productOwner,
    runtimeApplicationId: application.id,
    contributionId,
    source,
    contribution: true,
  })))
  componentClaims.push(...application.componentNames.map((name) => ({
    prefix: name,
    exact: true,
    productOwner: application.productOwner,
    runtimeApplicationId: application.id,
    contributionId,
    source,
    contribution: true,
  })))
}

for (const { source, raw } of contributionEntries) {
  if (raw.extends_application === undefined) continue
  assertExactKeys(
    raw,
    [
      'schema_version',
      'contribution_id',
      'product_owner',
      'runtime_owner',
      'extends_application',
      'component_prefixes',
      'component_names',
      'routes',
      'styles',
      'locales',
      'capabilities',
      'error_boundary',
      'adapter_module',
      'page_roots',
      'draft_contract',
      'navigation',
      'budget',
      'renderer_adapter',
      'exclusive_renderer',
      'renderer_runtime_kind',
      'renderer_entrypoint',
      'renderer_shell_adapter',
      'renderer_ui_adapter',
      'renderer_preview_kind',
      'renderer_manifest_path',
    ],
    source,
    [
      'schema_version',
      'contribution_id',
      'product_owner',
      'runtime_owner',
      'extends_application',
    ],
  )
  const contributionId = stringValue(raw.contribution_id, source, 'contribution_id')
  const targetId = identifierValue(raw.extends_application, source, 'extends_application')
  const target = applications.get(targetId)
  if (!target) manifestError(source, `unknown extended application ${targetId}`)
  const productOwner = ownerValue(raw.product_owner, source, 'product_owner')
  const runtimeOwner = ownerValue(raw.runtime_owner, source, 'runtime_owner')
  const rendererReplacement = raw.renderer_adapter !== undefined
    && raw.exclusive_renderer === true
    && target.id === 'website'
  if (runtimeOwner !== target.runtimeOwner && !rendererReplacement) {
    manifestError(source, `runtime_owner must match ${target.id} runtime owner ${target.runtimeOwner}`)
  }

  const prefixes = uniqueStrings(
    raw.component_prefixes ?? [],
    source,
    'component_prefixes',
    { pattern: COMPONENT_PREFIX },
  )
  target.componentPrefixes.push(...prefixes)
  componentClaims.push(...prefixes.map((prefix) => ({
    prefix,
    exact: false,
    productOwner,
    runtimeApplicationId: target.id,
    contributionId,
    source,
    contribution: true,
  })))
  const componentNames = uniqueStrings(
    raw.component_names ?? [],
    source,
    'component_names',
    { pattern: /^[A-Z][A-Za-z0-9]*(?:\/[A-Z][A-Za-z0-9]*)*$/ },
  )
  target.componentNames.push(...componentNames)
  componentClaims.push(...componentNames.map((name) => ({
    prefix: name,
    exact: true,
    productOwner,
    runtimeApplicationId: target.id,
    contributionId,
    source,
    contribution: true,
  })))
  const contributionStyles = uniqueStrings(raw.styles ?? [], source, 'styles')
  const contributionLocales = uniqueStrings(raw.locales ?? [], source, 'locales')
  target.styles.push(...contributionStyles)
  target.locales.push(...contributionLocales)
  target.capabilities.push(...uniqueStrings(raw.capabilities ?? [], source, 'capabilities'))
  const contributionErrorBoundary = raw.error_boundary === undefined
    ? null
    : stringValue(raw.error_boundary, source, 'error_boundary')
  if (contributionErrorBoundary) target.errorBoundaries.push(contributionErrorBoundary)
  const contributionNavigation = buildNavigation(raw.navigation ?? [], source)
  const adapterRequired = !rendererReplacement && (prefixes.length > 0
    || componentNames.length > 0
    || arrayValue(raw.styles ?? [], source, 'styles').length > 0
    || arrayValue(raw.locales ?? [], source, 'locales').length > 0
    || raw.error_boundary !== undefined
    || raw.draft_contract !== undefined
    || contributionNavigation.length > 0)
  if (adapterRequired && raw.adapter_module === undefined) {
    manifestError(source, 'frontend resource/page extensions require adapter_module')
  }
  if (adapterRequired && raw.budget === undefined) {
    manifestError(source, 'frontend resource/page extensions require budget')
  }
  if (raw.adapter_module !== undefined) {
    target.adapterModules.push(adapterModuleValue(raw.adapter_module, source, target.id))
  }
  const contributionAdapterModule = raw.adapter_module === undefined
    ? null
    : adapterModuleValue(raw.adapter_module, source, target.id)
  const contributionPageRoots = pageRootsValue(raw.page_roots, source)
  const contributionBudget = raw.budget === undefined ? null : buildBudget(raw.budget, source)
  target.contributions.push({
    id: contributionId,
    productOwner,
    runtimeOwner,
    adapterModule: contributionAdapterModule,
    pageRoots: contributionPageRoots,
    styles: contributionStyles,
    locales: contributionLocales,
    errorBoundary: contributionErrorBoundary,
    draftContract: raw.draft_contract === undefined
      ? null
      : buildDraftContract(raw.draft_contract, source),
    navigation: contributionNavigation,
    budget: contributionBudget,
  })
  if (contributionBudget && !rendererReplacement) {
    target.budget = mergeApplicationBudget(target.budget, contributionBudget)
  }

  const contributionRoutes = arrayValue(raw.routes ?? [], source, 'routes').map((rule, index) => (
    buildRouteRule(
      rule,
      `${source}#routes[${index}]`,
      target.id,
      productOwner,
      true,
      contributionId,
    )
  ))
  target.routeRules.push(...contributionRoutes)
  routeRules.push(...contributionRoutes)

  if (raw.renderer_adapter !== undefined) {
    const rendererAdapter = adapterNameValue(raw.renderer_adapter, source, 'renderer_adapter')
    if (target.id !== 'website' || raw.exclusive_renderer !== true) {
      manifestError(source, 'renderer adapters may only exclusively replace Website')
    }
    if (target.rendererAdapters.length > 0
      && !(target.rendererAdapters.length === 1
        && target.rendererAdapters[0] === 'ce_inertia_document')) {
      manifestError(source, `Website renderer already supplied by ${target.rendererAdapters[0]}`)
    }
    if (raw.adapter_module !== undefined
      || raw.draft_contract !== undefined
      || prefixes.length > 0
      || componentNames.length > 0
      || arrayValue(raw.capabilities ?? [], source, 'capabilities').length > 0
      || contributionNavigation.length > 0
      || target.adapterModules.length > 0
      || target.contributions.some((contribution) => contribution.id !== contributionId)) {
      manifestError(
        source,
        'exclusive Website renderer cannot share Inertia adapters, pages, navigation, or draft resources',
      )
    }
    if (contributionRoutes.some((route) => (
      route.kind !== 'document' && route.kind !== 'download' && route.kind !== 'api'
    ))) {
      manifestError(source, 'exclusive Website renderer routes must be document, download, or api')
    }
    const rendererRuntimeKind = stringValue(
      raw.renderer_runtime_kind,
      source,
      'renderer_runtime_kind',
    ) as FrontendRuntimeKind
    if (rendererRuntimeKind !== 'inertia_document' && rendererRuntimeKind !== 'astro_document') {
      manifestError(source, 'exclusive Website renderer requires a document runtime')
    }
    if (contributionStyles.length === 0 || contributionLocales.length === 0
      || !contributionErrorBoundary || raw.budget === undefined) {
      manifestError(source, 'exclusive Website renderer requires styles, locales, error, and budget')
    }
    target.runtimeOwner = runtimeOwner
    target.runtimeKind = rendererRuntimeKind
    target.entrypoint = entrypointValue(raw.renderer_entrypoint, source, 'renderer_entrypoint')
    target.shellAdapter = adapterNameValue(
      raw.renderer_shell_adapter,
      source,
      'renderer_shell_adapter',
    )
    target.uiAdapter = adapterNameValue(raw.renderer_ui_adapter, source, 'renderer_ui_adapter')
    if (rendererRuntimeKind === 'astro_document' && target.uiAdapter !== 'astro_custom') {
      manifestError(source, 'Astro Website renderer must use the isolated astro_custom UI adapter')
    }
    target.styles.splice(0, target.styles.length, ...contributionStyles)
    target.locales.splice(0, target.locales.length, ...contributionLocales)
    target.errorBoundaries.splice(0, target.errorBoundaries.length, contributionErrorBoundary)
    target.budget = buildBudget(raw.budget, source)
    target.rendererAdapters.splice(0, target.rendererAdapters.length, rendererAdapter)
    const rendererPreviewKind = stringValue(
      raw.renderer_preview_kind,
      source,
      'renderer_preview_kind',
    )
    if (rendererPreviewKind !== 'inertia_canvas' && rendererPreviewKind !== 'document_frame') {
      manifestError(source, 'exclusive Website renderer requires a supported preview kind')
    }
    const rendererManifestPath = rendererRuntimeKind === 'astro_document'
      ? repositoryPathValue(raw.renderer_manifest_path, source, 'renderer_manifest_path')
      : null
    if (rendererRuntimeKind !== 'astro_document' && raw.renderer_manifest_path !== undefined) {
      manifestError(source, 'renderer_manifest_path applies only to Astro document renderers')
    }
    target.renderer = {
      adapter: rendererAdapter,
      contributionId,
      productOwner,
      runtimeOwner,
      previewKind: rendererPreviewKind,
      manifestPath: rendererManifestPath,
    }
  }
}

const sharedRoutes = objectValue(sharedRoutesManifest, 'config/frontend_applications/shared_routes.json')
if (sharedRoutes.schema_version !== 1) {
  manifestError('config/frontend_applications/shared_routes.json', 'schema_version must be 1')
}
routeRules.push(...arrayValue(sharedRoutes.routes, 'shared routes', 'routes').map((rule, index) => (
  buildRouteRule(rule, `shared_routes.json#routes[${index}]`, null, 'ce')
)))

const adapterModuleClaims = new Map<string, FrontendApplicationContribution>()
for (const application of applications.values()) {
  for (const values of [
    application.componentPrefixes,
    application.componentNames,
    application.styles,
    application.locales,
    application.errorBoundaries,
    application.capabilities,
    application.adapterModules,
  ]) {
    if (new Set(values).size !== values.length) {
      manifestError(application.source, `application ${application.id} has duplicate resources`)
    }
  }
  if (application.id !== 'website' && application.rendererAdapters.length > 0) {
    manifestError(application.source, 'only Website may declare a document renderer adapter')
  }
  if (application.id === 'website') {
    const renderer = application.renderer
    const rendererContribution = renderer?.contributionId
      ? application.contributions.find((contribution) => contribution.id === renderer.contributionId)
      : null
    const validBaseRenderer = renderer?.contributionId === null
      && renderer.productOwner === application.productOwner
      && renderer.runtimeOwner === application.runtimeOwner
    const validContributionRenderer = Boolean(rendererContribution
      && rendererContribution.productOwner === renderer?.productOwner
      && rendererContribution.runtimeOwner === renderer?.runtimeOwner)
    if (!renderer
      || renderer.adapter !== application.rendererAdapters[0]
      || renderer.runtimeOwner !== application.runtimeOwner
      || (!validBaseRenderer && !validContributionRenderer)) {
      manifestError(application.source, 'Website renderer identity is incomplete or inconsistent')
    }
  }
  if (application.id !== 'website' && application.uiAdapter !== 'mcweb_ui') {
    manifestError(application.source, `${application.id} must use the mcweb_ui adapter`)
  }
  for (const contribution of application.contributions) {
    if (contribution.draftContract
      && !application.capabilities.includes(contribution.draftContract.capability)) {
      manifestError(
        application.source,
        `draft capability ${contribution.draftContract.capability} is not declared by ${application.id}`,
      )
    }
    if (contribution.adapterModule) {
      const previous = adapterModuleClaims.get(contribution.adapterModule)
      if (previous) {
        manifestError(
          application.source,
          `adapter module ${contribution.adapterModule} is shared by ${previous.id} and ${contribution.id}`,
        )
      }
      adapterModuleClaims.set(contribution.adapterModule, contribution)
    }
  }
  const ownedAdapterModules = application.contributions
    .flatMap((contribution) => contribution.adapterModule ? [contribution.adapterModule] : [])
  if (ownedAdapterModules.length !== application.adapterModules.length
    || ownedAdapterModules.some((modulePath) => !application.adapterModules.includes(modulePath))) {
    manifestError(application.source, `${application.id} has adapter modules without contribution owners`)
  }

  for (const projection of application.projections) {
    const owner = applications.get(projection.ownerApplication)
    if (!owner) manifestError(application.source, `unknown projection owner ${projection.ownerApplication}`)
    if (!owner.componentPrefixes.some((prefix) => (
      projection.prefix.startsWith(prefix) || prefix.startsWith(projection.prefix)
    ))) {
      manifestError(
        application.source,
        `projection ${projection.prefix} is not owned by ${projection.ownerApplication}`,
      )
    }
  }
}

for (let leftIndex = 0; leftIndex < componentClaims.length; leftIndex += 1) {
  for (let rightIndex = leftIndex + 1; rightIndex < componentClaims.length; rightIndex += 1) {
    const left = componentClaims[leftIndex]
    const right = componentClaims[rightIndex]
    const overlaps = left.exact && right.exact
      ? left.prefix === right.prefix
      : left.exact
        ? left.prefix.startsWith(right.prefix)
        : right.exact
          ? right.prefix.startsWith(left.prefix)
          : left.prefix.startsWith(right.prefix) || right.prefix.startsWith(left.prefix)
    if (!overlaps) continue
    if (left.prefix === right.prefix && left.exact === right.exact) {
      manifestError(left.source, `duplicate component prefix ${left.prefix} also declared by ${right.source}`)
    }
    if (left.contribution && right.contribution) {
      manifestError(left.source, `sibling contribution overlaps ${right.source}`)
    }
    const [parent, child] = left.exact && !right.exact
      ? [right, left]
      : right.exact && !left.exact
        ? [left, right]
        : left.prefix.length < right.prefix.length
          ? [left, right]
          : [right, left]
    const parentApplication = applications.get(parent.runtimeApplicationId)
    if (!parentApplication?.allowDescendantContributions || !child.contribution) {
      manifestError(
        child.source,
        `component prefix ${child.prefix} overlaps closed parent ${parent.prefix}`,
      )
    }
  }
}
componentClaims.sort((left, right) => right.prefix.length - left.prefix.length
  || left.prefix.localeCompare(right.prefix))
componentClaims.forEach((claim) => Object.freeze(claim))

function routeLiteralPrefix(pattern: string): string {
  const wildcard = pattern.indexOf('*')
  return wildcard === -1 ? pattern : pattern.slice(0, wildcard)
}

function routePatternsOverlap(left: FrontendRouteRule, right: FrontendRouteRule): boolean {
  const leftSegments = left.pattern.split('/')
  const rightSegments = right.pattern.split('/')
  const memo = new Map<string, boolean>()
  const segmentExpression = (pattern: string) => new RegExp(
    `^${pattern.replace(/[.+?^${}()|[\]\\]/g, '\\$&').replaceAll('*', '.*')}$`,
  )
  const segmentIntersects = (leftSegment: string, rightSegment: string) => {
    if (leftSegment === '*' || rightSegment === '*') return true
    if (!leftSegment.includes('*') && !rightSegment.includes('*')) {
      return leftSegment === rightSegment
    }
    if (!rightSegment.includes('*')) return segmentExpression(leftSegment).test(rightSegment)
    if (!leftSegment.includes('*')) return segmentExpression(rightSegment).test(leftSegment)
    const leftSuffix = leftSegment.split('*', 2)[1] ?? ''
    const rightSuffix = rightSegment.split('*', 2)[1] ?? ''
    return leftSuffix.endsWith(rightSuffix) || rightSuffix.endsWith(leftSuffix)
  }
  const overlaps = (leftIndex: number, rightIndex: number): boolean => {
    const key = `${leftIndex}:${rightIndex}`
    const cached = memo.get(key)
    if (cached !== undefined) return cached
    if (leftIndex === leftSegments.length && rightIndex === rightSegments.length) return true
    if (leftIndex === leftSegments.length) {
      return rightSegments.slice(rightIndex).every((segment) => segment === '**')
    }
    if (rightIndex === rightSegments.length) {
      return leftSegments.slice(leftIndex).every((segment) => segment === '**')
    }
    const leftSegment = leftSegments[leftIndex]
    const rightSegment = rightSegments[rightIndex]
    let result: boolean
    if (leftSegment === '**' && rightSegment === '**') {
      result = overlaps(leftIndex + 1, rightIndex) || overlaps(leftIndex, rightIndex + 1)
    } else if (leftSegment === '**') {
      result = overlaps(leftIndex + 1, rightIndex) || overlaps(leftIndex, rightIndex + 1)
    } else if (rightSegment === '**') {
      result = overlaps(leftIndex, rightIndex + 1) || overlaps(leftIndex + 1, rightIndex)
    } else {
      result = segmentIntersects(leftSegment, rightSegment)
        && overlaps(leftIndex + 1, rightIndex + 1)
    }
    memo.set(key, result)
    return result
  }
  return overlaps(0, 0)
}

function strictDescendantRoute(childPattern: string, parentPattern: string): boolean {
  if (parentPattern.endsWith('/**')) {
    const parentRoot = parentPattern.slice(0, -2)
    return childPattern !== parentPattern && childPattern.startsWith(parentRoot)
  }
  const childPrefix = routeLiteralPrefix(childPattern)
  const parentPrefix = routeLiteralPrefix(parentPattern)
  return parentPattern.includes('*')
    && childPrefix.startsWith(parentPrefix)
    && childPrefix.length > parentPrefix.length
    && childPattern !== parentPattern
}

function websiteFallbackRoute(rule: FrontendRouteRule): boolean {
  return rule.applicationId === 'website' && rule.pattern === '/*'
}

function validateRouteOverlap(left: FrontendRouteRule, right: FrontendRouteRule): void {
  const sameApplication = left.applicationId === right.applicationId
  const sameProductOwner = left.productOwner === right.productOwner
  const sameContribution = left.contribution === right.contribution
    && left.contributionId === right.contributionId
  if (sameApplication && sameProductOwner && sameContribution) {
    if (left.kind === right.kind) return
    if ((strictDescendantRoute(left.pattern, right.pattern) && left.priority > right.priority)
      || (strictDescendantRoute(right.pattern, left.pattern) && right.priority > left.priority)) return
    manifestError(
      left.source,
      `overlapping route kinds require a higher-priority strict descendant of ${right.source}`,
    )
  }

  if (left.applicationId === null || right.applicationId === null) {
    const [shared, owned] = left.applicationId === null ? [left, right] : [right, left]
    if (shared.priority > owned.priority) return
    manifestError(shared.source, `shared route must outrank overlapping ${owned.source}`)
  }

  if (websiteFallbackRoute(left) || websiteFallbackRoute(right)) {
    const [fallback, owned] = websiteFallbackRoute(left) ? [left, right] : [right, left]
    if (owned.priority > fallback.priority) return
    manifestError(fallback.source, `Website fallback must rank below ${owned.source}`)
  }

  const previewAdmin = [left.applicationId, right.applicationId]
    .sort()
    .join(':') === 'admin:website_preview'
  if (previewAdmin) {
    const [preview, admin] = left.applicationId === 'website_preview'
      ? [left, right]
      : [right, left]
    if (preview.priority > admin.priority) return
    manifestError(preview.source, `Website Preview route must outrank ${admin.source}`)
  }

  if (sameApplication) {
    if (left.contribution && right.contribution) {
      manifestError(
        left.source,
        `distinct contributions may not overlap routes with ${right.source}`,
      )
    }
    const [child, parent] = left.contribution && !right.contribution
      ? [left, right]
      : [right, left]
    if (child.contribution
      && strictDescendantRoute(child.pattern, parent.pattern)
      && child.priority > parent.priority) return
    manifestError(
      child.source,
      `contribution route must be a higher-priority strict descendant of ${parent.source}`,
    )
  }

  manifestError(left.source, `overlapping route has a different runtime in ${right.source}`)
}

const routeClaims = new Map<string, FrontendRouteRule>()
for (const rule of routeRules) {
  for (const method of rule.methods) {
    const key = `${method} ${rule.pattern}`
    const previous = routeClaims.get(key)
    if (previous) manifestError(rule.source, `duplicate route claim ${key} from ${previous.source}`)
    routeClaims.set(key, rule)
  }
  if (rule.kind === 'shared_action') {
    const unknown = rule.allowedSourceApplications.filter((id) => !applications.has(id))
    const knownCapabilities = new Set(
      [...applications.values()].flatMap((application) => application.capabilities),
    )
    const unknownCapabilities = rule.allowedSourceCapabilities
      .filter((capability) => !knownCapabilities.has(capability))
    if (unknown.length > 0 || unknownCapabilities.length > 0) {
      manifestError(
        rule.source,
        `unknown allowed sources ids=${unknown.join(', ')} capabilities=${unknownCapabilities.join(', ')}`,
      )
    }
  }
}

for (let leftIndex = 0; leftIndex < routeRules.length; leftIndex += 1) {
  for (let rightIndex = leftIndex + 1; rightIndex < routeRules.length; rightIndex += 1) {
    const left = routeRules[leftIndex]
    const right = routeRules[rightIndex]
    if (!left.methods.some((method) => right.methods.includes(method))) continue
    if (!routePatternsOverlap(left, right)) continue
    validateRouteOverlap(left, right)
  }
}

routeRules.sort((left, right) => right.priority - left.priority
  || right.pattern.replaceAll('*', '').length - left.pattern.replaceAll('*', '').length
  || left.pattern.localeCompare(right.pattern)
  || (left.applicationId ?? '').localeCompare(right.applicationId ?? ''))
routeRules.forEach((rule) => {
  Object.freeze(rule.methods)
  Object.freeze(rule.allowedSourceApplications)
  Object.freeze(rule.allowedSourceCapabilities)
  Object.freeze(rule)
})

const compiledRouteRules = routeRules.map((rule) => ({
  rule,
  matcher: routePatternExpression(rule.pattern),
}))

for (const rule of routeRules) {
  if (!rule.safeGetPath) continue
  const recovery = compiledRouteRules.find(({ rule: candidate, matcher }) => (
    candidate.methods.includes('GET') && matcher.test(rule.safeGetPath as string)
  ))
  if (!recovery || (recovery.rule.kind !== 'document' && recovery.rule.kind !== 'inertia_page')) {
    manifestError(
      rule.source,
      `safe_get_path ${rule.safeGetPath} must resolve to a GET document or Inertia page`,
    )
  }
}

const launchers = [...applications.values()].flatMap((application) => (
  application.launcher
    ? [{ ...application.launcher, applicationId: application.id, source: application.source }]
    : []
))
const launchersByPath = new Map<string, typeof launchers>()
for (const launcher of launchers) {
  const candidates = launchersByPath.get(launcher.path) ?? []
  candidates.push(launcher)
  launchersByPath.set(launcher.path, candidates)
}
for (const [path, candidates] of launchersByPath) {
  const priorities = new Set<number>()
  for (const launcher of candidates) {
    if (priorities.has(launcher.priority)) {
      manifestError(launcher.source, `launcher ${path} has duplicate priority ${launcher.priority}`)
    }
    priorities.add(launcher.priority)
  }
  const route = compiledRouteRules.find(({ rule, matcher }) => (
    rule.methods.includes('GET') && matcher.test(path)
  ))
  if (route?.rule.kind !== 'document') {
    manifestError(candidates[0].source, `launcher ${path} requires a canonical GET document route`)
  }
}
launchers.sort((left, right) => left.path.localeCompare(right.path)
  || right.priority - left.priority
  || left.applicationId.localeCompare(right.applicationId))

function freezeApplication(application: MutableApplication): FrontendApplicationDescriptor {
  const freezeBudget = (budget: FrontendApplicationBudget): FrontendApplicationBudget => (
    Object.freeze({
      ...budget,
      representativePaths: Object.freeze([...budget.representativePaths]),
      representativeComponents: Object.freeze([...budget.representativeComponents]),
      representativeEntries: Object.freeze([...budget.representativeEntries]),
    })
  )
  return Object.freeze({
    id: application.id,
    productOwner: application.productOwner,
    runtimeOwner: application.runtimeOwner,
    runtimeKind: application.runtimeKind,
    entrypoint: application.entrypoint,
    landingPath: application.landingPath,
    componentPrefixes: Object.freeze([...application.componentPrefixes]),
    componentNames: Object.freeze([...application.componentNames]),
    allowDescendantContributions: application.allowDescendantContributions,
    projections: Object.freeze(application.projections.map((projection) => Object.freeze({
      ...projection,
    }))),
    shellAdapter: application.shellAdapter,
    uiAdapter: application.uiAdapter,
    styles: Object.freeze([...application.styles]),
    locales: Object.freeze([...application.locales]),
    errorBoundaries: Object.freeze([...application.errorBoundaries]),
    capabilities: Object.freeze([...application.capabilities]),
    budget: freezeBudget(application.budget),
    launcher: application.launcher ? Object.freeze({ ...application.launcher }) : null,
    rendererAdapters: Object.freeze([...application.rendererAdapters]),
    renderer: application.renderer ? Object.freeze({ ...application.renderer }) : null,
    adapterModules: Object.freeze([...application.adapterModules]),
    contributions: Object.freeze(application.contributions.map((contribution) => Object.freeze({
      ...contribution,
      pageRoots: Object.freeze([...contribution.pageRoots]),
      styles: Object.freeze([...contribution.styles]),
      locales: Object.freeze([...contribution.locales]),
      draftContract: contribution.draftContract
        ? Object.freeze({ ...contribution.draftContract })
        : null,
      navigation: Object.freeze(contribution.navigation.map((group) => Object.freeze({
        ...group,
        items: Object.freeze(group.items.map((item) => Object.freeze({ ...item }))),
      }))),
      budget: contribution.budget ? freezeBudget(contribution.budget) : null,
    }))),
  })
}

const frozenApplications = new Map(
  [...applications.entries()].map(([id, application]) => [id, freezeApplication(application)]),
)

export const frontendApplications = Object.freeze(
  [...frozenApplications.values()].sort((left, right) => left.id.localeCompare(right.id)),
)

export const frontendRouteRules = Object.freeze([...routeRules])

export function frontendApplication(id: string): FrontendApplicationDescriptor | null {
  return frozenApplications.get(id) ?? null
}

export function requireFrontendApplication(id: string): FrontendApplicationDescriptor {
  const application = frontendApplication(id)
  if (!application) throw new Error(`Unknown frontend application: ${id}`)
  return application
}

export function frontendLauncherApplication(
  path = '/app',
): FrontendApplicationDescriptor | null {
  const launcher = launchers.find((candidate) => candidate.path === path)
  return launcher ? requireFrontendApplication(launcher.applicationId) : null
}

export function resolveFrontendRoute(
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

export function frontendComponentOwner(component: string): Readonly<ComponentClaim> | null {
  if (!component || component.startsWith('/') || component.endsWith('/')
    || component.includes('\\') || component.includes('..')) return null
  return componentClaims.find((claim) => (
    claim.exact ? component === claim.prefix : component.startsWith(claim.prefix)
  )) ?? null
}

export function assertFrontendComponent(
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

for (const application of frontendApplications) {
  for (let index = 0; index < application.budget.representativePaths.length; index += 1) {
    const path = application.budget.representativePaths[index]
    const route = resolveFrontendRoute(path, 'GET')
    if (route?.application?.id !== application.id
      || (route.rule.kind !== 'inertia_page' && route.rule.kind !== 'document')) {
      manifestError(
        application.id,
        `budget path ${path} does not resolve to an owned GET page/document`,
      )
    }
  }
  for (const component of application.budget.representativeComponents) {
    assertFrontendComponent(application.id, component)
  }
  for (const contribution of application.contributions) {
    for (const group of contribution.navigation) {
      for (const item of group.items) {
        const route = resolveFrontendRoute(item.href, 'GET')
        if (route?.application?.id !== application.id
          || route.rule.kind !== 'inertia_page'
          || route.rule.contributionId !== contribution.id) {
          manifestError(
            contribution.id,
            `navigation href ${item.href} is not an owned contribution page`,
          )
        }
      }
    }
    if (!contribution.budget) continue
    for (const path of contribution.budget.representativePaths) {
      const route = resolveFrontendRoute(path, 'GET')
      const rendererBudget = application.renderer?.contributionId === contribution.id
      if (route?.application?.id !== application.id
        || (route.rule.kind !== 'inertia_page' && route.rule.kind !== 'document')
        || (!rendererBudget && route.rule.contributionId !== contribution.id)) {
        manifestError(
          contribution.id,
          `contribution budget path ${path} is not owned by ${contribution.id}`,
        )
      }
    }
    for (const component of contribution.budget.representativeComponents) {
      const owner = assertFrontendComponent(application.id, component)
      if (contribution.adapterModule && owner.contributionId !== contribution.id) {
        manifestError(
          contribution.id,
          `contribution budget component ${component} belongs to ${owner.contributionId ?? 'base'}`,
        )
      }
    }
  }
}

export function frontendApplicationRequestHeaders(
  applicationId: string,
): Record<string, string> {
  requireFrontendApplication(applicationId)
  return { [FRONTEND_APPLICATION_HEADER]: applicationId }
}

export function documentFrontendApplicationId(): string {
  const id = document.documentElement.dataset.mcwebApplication
  if (!id) throw new Error('Document has no frontend application identity')
  requireFrontendApplication(id)
  return id
}

export function frontendRouteSourceAllowed(
  routeMatch: FrontendRouteMatch,
  sourceApplicationId: string,
): boolean {
  const source = frontendApplication(sourceApplicationId)
  if (!source) return false
  return routeMatch.rule.allowedSourceApplications.includes(source.id)
    || routeMatch.rule.allowedSourceCapabilities
      .some((capability) => source.capabilities.includes(capability))
}
