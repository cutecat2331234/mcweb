import assert from 'node:assert/strict'
import { EventEmitter } from 'node:events'
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import test, { type TestContext } from 'node:test'
import { createFrontendApplicationRegistry } from '../../app/javascript/lib/frontendApplicationRegistry.ts'
import { compileFrontendApplicationRegistry } from '../../scripts/frontend-application-registry-compiler.ts'
import {
  FRONTEND_APPLICATION_REGISTRY_MODULE,
  frontendApplicationRegistryModuleSource,
  frontendApplicationRegistryPlugin,
} from '../../scripts/frontend-application-registry-plugin.ts'
import {
  readFrontendApplicationManifests,
  readFrontendApplicationRegistry,
} from '../../scripts/frontend-application-registry.ts'

const root = process.cwd()
const forumSource = 'config/frontend_applications/base/forum.json'
const contributionSource = 'config/frontend_applications/contributions/registry_probe.json'

// Mutable JSON fixtures exercise the real compiler, without maintaining a
// second hand-written registry or running Vite in these focused contracts.
function manifests() {
  const { sources } = readFrontendApplicationManifests(root)
  return structuredClone(sources) as {
    baseManifestModules: Record<string, any>
    contributionManifestModules: Record<string, any>
    sharedRoutesManifest: { schema_version: number; routes: any[] }
  }
}

function withContribution() {
  const sources = manifests()
  sources.contributionManifestModules[contributionSource] = {
    schema_version: 1,
    contribution_id: 'test.registry_probe',
    product_owner: 'test_extension',
    runtime_owner: sources.baseManifestModules[forumSource].runtime_owner,
    extends_application: 'forum',
    component_prefixes: ['RegistryProbe/'],
    adapter_module: 'app/javascript/frontend-application-adapters/forum/registry-probe.ts',
    page_roots: ['app/javascript/pages'],
    accessories: ['registry_probe'],
    draft_contract: {
      capability: 'server_drafts',
      key_namespace: 'registry_probe',
      version: 1,
      user_scoped: true,
      resource_scoped: true,
      offline_recovery: true,
      clear_on_submit: true,
    },
    navigation: [{
      id: 'registry_probe',
      label_key: 'forum.registryProbe',
      items: [{
        href: '/app/forum/registry-probe',
        label_key: 'forum.registryProbe',
        visibility_prop: 'registry_probe.visible',
        module_key: 'forum',
        permission_key: 'registry_probe.read',
        permission_any: ['registry_probe.read', 'registry_probe.admin'],
        capability_key: 'registry_probe',
        requires_authentication: true,
      }],
    }],
    budget: {
      representative_paths: ['/app/forum/registry-probe'],
      representative_components: ['RegistryProbe/Index'],
      max_initial_javascript_bytes: 650000,
    },
    routes: [{
      kind: 'inertia_page',
      methods: ['GET', 'HEAD'],
      pattern: '/app/forum/registry-probe',
      priority: 2000,
    }],
  }
  return sources
}

function assertDeeplyFrozen(value: unknown): void {
  if (value === null || typeof value !== 'object') return
  assert.ok(Object.isFrozen(value))
  for (const child of Object.values(value)) assertDeeplyFrozen(child)
}

function temporaryRepository(t: TestContext) {
  const repository = mkdtempSync(join(tmpdir(), 'mcweb-registry-'))
  t.after(() => rmSync(repository, { recursive: true, force: true }))
  const sources = manifests()
  for (const [source, manifest] of Object.entries({
    ...sources.baseManifestModules,
    ...sources.contributionManifestModules,
    'config/frontend_applications/shared_routes.json': sources.sharedRoutesManifest,
  })) {
    const file = resolve(repository, source)
    mkdirSync(dirname(file), { recursive: true })
    writeFileSync(file, JSON.stringify(manifest))
  }
  return repository
}

function pluginHook(plugin: ReturnType<typeof frontendApplicationRegistryPlugin>, name: string) {
  const hook = plugin[name as keyof typeof plugin]
  assert.equal(typeof hook, 'function', `${name} must remain an inspectable plugin hook`)
  return hook as (...args: any[]) => any
}

test('the compiler emits deterministic data-only modules from the current manifests', () => {
  const sources = manifests()
  const compiled = compileFrontendApplicationRegistry(sources)
  const moduleSource = frontendApplicationRegistryModuleSource(compiled)
  assert.ok(moduleSource.startsWith('export default '))
  assert.ok(moduleSource.endsWith(';\n'))
  // Parsing the entire export as JSON excludes an executable validator/import
  // hidden in the virtual module, not merely a known list of compiler symbols.
  const serialized = JSON.parse(moduleSource.slice('export default '.length, -2))
  assert.deepEqual(serialized, compiled)
  assert.equal(frontendApplicationRegistryModuleSource(compileFrontendApplicationRegistry(sources)), moduleSource)
  const reversed = {
    ...sources,
    baseManifestModules: Object.fromEntries(Object.entries(sources.baseManifestModules).reverse()),
    contributionManifestModules: Object.fromEntries(Object.entries(sources.contributionManifestModules).reverse()),
  }
  assert.equal(frontendApplicationRegistryModuleSource(compileFrontendApplicationRegistry(reversed)), moduleSource)
  assertDeeplyFrozen(compiled)
  const runtime = createFrontendApplicationRegistry(serialized)
  assertDeeplyFrozen(serialized)
  assert.equal(runtime.resolveFrontendRoute('/app/forum/latest')?.application?.id, 'forum')
  assert.equal(runtime.resolveFrontendRoute('/app/forum/latest')?.rule.kind, 'inertia_page')
  assert.equal(runtime.resolveFrontendRoute('/app/identity/sign-in')?.application?.id, 'account')
})

test('serialized contributions preserve ownership, navigation grants and adapter diagnostics', () => {
  const data = JSON.parse(JSON.stringify(compileFrontendApplicationRegistry(withContribution())))
  const runtime = createFrontendApplicationRegistry(data)
  const contribution = runtime.requireFrontendApplication('forum').contributions
    .find((candidate) => candidate.id === 'test.registry_probe')
  assert.ok(contribution)
  assert.equal(contribution.navigation[0].items[0].visibilityProp, 'registry_probe.visible')
  assert.equal(contribution.navigation[0].items[0].moduleKey, 'forum')
  assert.equal(contribution.navigation[0].items[0].permissionKey, 'registry_probe.read')
  assert.deepEqual(contribution.navigation[0].items[0].permissionAny, ['registry_probe.read', 'registry_probe.admin'])
  assert.equal(contribution.navigation[0].items[0].capabilityKey, 'registry_probe')
  assert.equal(contribution.navigation[0].items[0].requiresAuthentication, true)
  assert.equal(contribution.draftContract?.keyNamespace, 'registry_probe')
  assert.deepEqual(contribution.pageRoots, ['app/javascript/pages'])
  assert.deepEqual(contribution.budget?.representativeComponents, ['RegistryProbe/Index'])
  assert.deepEqual(contribution.accessories, ['registry_probe'])
  assertDeeplyFrozen(contribution)
  assert.equal(runtime.assertFrontendComponent('forum', 'RegistryProbe/Index').contributionId, contribution.id)
  assert.throws(() => runtime.assertFrontendComponent('account', 'RegistryProbe/Index'), /cannot resolve/)
  assert.throws(() => runtime.assertFrontendComponent('forum', 'RegistryProbe/Index', 'ce'), /Route owner ce cannot resolve/)
  assert.equal(runtime.resolveFrontendRoute('/app/forum/registry-probe')?.rule.productOwner, 'test_extension')
  assert.equal(runtime.resolveFrontendRoute('/app/forum/registry-probe')?.rule.contributionId, contribution.id)
})

test('runtime route selection, document identity and shared-action headers remain fail-closed', (t) => {
  const sources = manifests()
  sources.sharedRoutesManifest.routes.push({ kind: 'api', methods: ['GET'], pattern: '/api', priority: 11000 })
  const runtime = createFrontendApplicationRegistry(compileFrontendApplicationRegistry(sources))
  assert.equal(runtime.resolveFrontendRoute('/api')?.rule.kind, 'api')
  assert.equal(runtime.resolveFrontendRoute('/api/example')?.rule.kind, 'api')
  assert.equal(runtime.resolveFrontendRoute('/app/forum/notifications')?.rule.kind, 'document')
  assert.equal(runtime.resolveFrontendRoute('/app/forum/latest', 'post')?.rule.kind, 'application_action')
  assert.equal(runtime.resolveFrontendRoute('//example.com/app/forum'), null)
  assert.equal(runtime.resolveFrontendRoute('/app\\forum'), null)
  assert.equal(runtime.frontendComponentOwner('../Community/Latest/Index'), null)
  assert.equal(runtime.frontendApplication('missing'), null)
  assert.throws(() => runtime.frontendApplicationRequestHeaders('missing'), /Unknown frontend application/)
  assert.deepEqual(runtime.frontendApplicationRequestHeaders('forum'), { 'X-McWeb-Application': 'forum' })
  const locale = runtime.resolveFrontendRoute('/locale', 'PATCH')
  assert.ok(locale)
  assert.equal(runtime.frontendRouteSourceAllowed(locale, 'forum'), true)
  assert.equal(runtime.frontendRouteSourceAllowed(locale, 'missing'), false)
  const documentDescriptor = Object.getOwnPropertyDescriptor(globalThis, 'document')
  t.after(() => {
    if (documentDescriptor) Object.defineProperty(globalThis, 'document', documentDescriptor)
    else Reflect.deleteProperty(globalThis, 'document')
  })
  const dataset: Record<string, string> = {}
  Object.defineProperty(globalThis, 'document', { configurable: true, value: { documentElement: { dataset } } })
  assert.throws(() => runtime.documentFrontendApplicationId(), /no frontend application identity/)
  dataset.mcwebApplication = 'missing'
  assert.throws(() => runtime.documentFrontendApplicationId(), /Unknown frontend application/)
  dataset.mcwebApplication = 'forum'
  assert.equal(runtime.documentFrontendApplicationId(), 'forum')
})

test('invalid schemas, overlaps, shared recovery and contribution boundaries fail during compilation', () => {
  const cases: [string, (sources: ReturnType<typeof manifests>) => void, RegExp][] = [
    ['schema keys', (sources) => { sources.baseManifestModules[forumSource].unknown = true }, /manifest keys mismatch/],
    ['cross-application route', (sources) => {
      sources.baseManifestModules[forumSource].routes.push({ kind: 'inertia_page', methods: ['GET'], pattern: '/app/store/registry-probe', priority: 2000 })
    }, /overlapping route has a different runtime/],
    ['shared capability', (sources) => { sources.sharedRoutesManifest.routes[0].allowed_source_capabilities = ['missing_capability'] }, /unknown allowed sources/],
    ['shared recovery', (sources) => { sources.sharedRoutesManifest.routes[0].safe_get_path = '/api/example' }, /safe_get_path.*GET document or Inertia page/],
    ['budget route ownership', (sources) => { sources.baseManifestModules[forumSource].budget.representative_paths[0] = '/app/identity/sign-in' }, /budget path.*owned GET page/],
    ['contribution runtime owner', (sources) => { sources.contributionManifestModules[contributionSource].runtime_owner = 'unknown' }, /runtime_owner must match/],
    ['contribution page root', (sources) => { sources.contributionManifestModules[contributionSource].page_roots = ['../pages'] }, /invalid page_roots/],
    ['contribution navigation ownership', (sources) => { sources.contributionManifestModules[contributionSource].navigation[0].items[0].href = '/app/forum/latest' }, /navigation href.*owned contribution page/],
    ['contribution locale key', (sources) => { sources.contributionManifestModules[contributionSource].navigation[0].label_key = 'not a key' }, /invalid label_key/],
    ['closed component ownership', (sources) => { sources.contributionManifestModules[contributionSource].component_prefixes = ['Community/RegistryProbe/'] }, /overlaps closed parent/],
    ['duplicate contribution identity', (sources) => {
      sources.contributionManifestModules['config/frontend_applications/contributions/duplicate.json'] = structuredClone(sources.contributionManifestModules[contributionSource])
    }, /duplicate contribution_id/],
  ]
  for (const [label, mutate, expected] of cases) {
    const sources = withContribution()
    mutate(sources)
    assert.throws(() => compileFrontendApplicationRegistry(sources), expected, label)
  }
})

test('Vite validates before entry loading and recompiles changed or missing manifests without a fallback', (t) => {
  const repository = temporaryRepository(t)
  const plugin = frontendApplicationRegistryPlugin(repository)
  const watched: string[] = []
  const context = { addWatchFile: (file: string) => watched.push(file) }
  pluginHook(plugin, 'buildStart').call(context)
  assert.ok(watched.includes(resolve(repository, forumSource)))
  assert.ok(watched.includes(resolve(repository, 'config/frontend_applications/contributions')))
  const id = pluginHook(plugin, 'resolveId')(FRONTEND_APPLICATION_REGISTRY_MODULE)
  assert.equal(id, `\0${FRONTEND_APPLICATION_REGISTRY_MODULE}`)
  const before = pluginHook(plugin, 'load').call(context, id)
  const changed = manifests().baseManifestModules[forumSource]
  changed.landing_path = '/app/forum/registry-probe'
  writeFileSync(resolve(repository, forumSource), JSON.stringify(changed))
  assert.notEqual(pluginHook(plugin, 'load').call(context, id), before)
  writeFileSync(resolve(repository, forumSource), '{ invalid JSON')
  assert.throws(() => pluginHook(plugin, 'buildStart').call(context), /Cannot read frontend application manifest.*forum.json/)
  assert.throws(() => pluginHook(plugin, 'load').call(context, id), /Cannot read frontend application manifest.*forum.json/)
  rmSync(resolve(repository, 'config/frontend_applications/shared_routes.json'))
  writeFileSync(resolve(repository, forumSource), JSON.stringify(changed))
  assert.throws(() => readFrontendApplicationRegistry(repository), /Cannot read frontend application manifest.*shared_routes.json/)
})

test('development additions, edits and removals invalidate the virtual registry and reload every application', () => {
  const plugin = frontendApplicationRegistryPlugin(root)
  const events = new EventEmitter()
  const watched: string[] = []
  const watcher = Object.assign(events, { add: (file: string) => watched.push(file) })
  const messages: unknown[] = []
  const invalidated: unknown[] = []
  const virtualModule = { id: `\0${FRONTEND_APPLICATION_REGISTRY_MODULE}` }
  pluginHook(plugin, 'configureServer')({
    watcher,
    moduleGraph: {
      getModuleById: (id: string) => id === virtualModule.id ? virtualModule : undefined,
      invalidateModule: (module: unknown) => invalidated.push(module),
    },
    ws: { send: (message: unknown) => messages.push(message) },
  })
  for (const event of ['add', 'change', 'unlink']) events.emit(event, resolve(root, contributionSource))
  events.emit('change', resolve(root, 'app/javascript/lib/frontendApplications.ts'))
  assert.equal(watched.length, 1)
  assert.deepEqual(invalidated, [virtualModule, virtualModule, virtualModule])
  assert.deepEqual(messages, [{ type: 'full-reload' }, { type: 'full-reload' }, { type: 'full-reload' }])
  pluginHook(plugin, 'closeBundle')()
  for (const event of ['add', 'change', 'unlink']) assert.equal(events.listenerCount(event), 0)
})

test('browser modules cannot import raw manifests or the validation closure', () => {
  for (const file of ['frontendApplications.ts', 'frontendApplicationRegistry.ts']) {
    const source = readFileSync(resolve(root, 'app/javascript/lib', file), 'utf8')
    assert.doesNotMatch(source, /import\.meta\.glob|manifestError|assertExactKeys|buildApplication|scripts\/frontend-application-registry|config\/frontend_applications/)
  }
  const facade = readFileSync(resolve(root, 'app/javascript/lib/frontendApplications.ts'), 'utf8')
  assert.match(facade, /from 'virtual:mcweb\/frontend-applications'/)
  const viteConfig = readFileSync(resolve(root, 'vite.config.ts'), 'utf8')
  assert.match(viteConfig, /frontendApplicationRegistryPlugin\(__dirname\)/)
  const boundaryChecker = readFileSync(resolve(root, 'scripts/check-frontend-application-boundaries.mjs'), 'utf8')
  assert.match(boundaryChecker, /readFrontendApplicationRegistry\(root\)/)
  const plugin = frontendApplicationRegistryPlugin(root)
  const context = { error: (message: string) => { throw new Error(message) } }
  const bundle = (id: string) => ({ startup: { type: 'chunk', fileName: 'startup.js', modules: { [id]: {} } } })
  for (const id of [
    resolve(root, 'scripts/frontend-application-registry-compiler.ts'),
    resolve(root, 'scripts/frontend-application-registry.ts'),
    resolve(root, 'scripts/frontend-application-registry-plugin.ts'),
    `${resolve(root, forumSource)}?import`,
  ]) {
    assert.throws(() => pluginHook(plugin, 'generateBundle').call(context, {}, bundle(id)), /Build-only frontend registry module leaked/)
  }
  assert.doesNotThrow(() => pluginHook(plugin, 'generateBundle').call(context, {}, bundle(`\0${FRONTEND_APPLICATION_REGISTRY_MODULE}`)))
  assert.doesNotThrow(() => pluginHook(plugin, 'generateBundle').call(context, {}, bundle(resolve(root, 'app/javascript/lib/frontendApplicationRegistry.ts'))))
})
