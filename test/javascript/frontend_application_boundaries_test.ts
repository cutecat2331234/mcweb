import assert from 'node:assert/strict'
import { existsSync, readFileSync, readdirSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

const root = process.cwd()
const entryRoot = resolve(root, 'app/javascript/entrypoints')
const websitePreviewManifest = readFileSync(
  resolve(root, 'config/frontend_applications/base/website_preview.json'),
  'utf8',
)
const boundaryChecker = readFileSync(
  resolve(root, 'scripts/check-frontend-application-boundaries.mjs'),
  'utf8',
)
const applications = [
  ['website-document.ts', ['Website/**/*.vue', 'Plugins/**/*.vue']],
  ['forum.ts', ['Community/**/*.vue']],
  ['store.ts', ['Commerce/**/*.vue', 'Payments/**/*.vue']],
  ['account.ts', ['Account/**/*.vue', 'Identity/**/*.vue', 'Minecraft/**/*.vue']],
  ['staff.ts', ['Staff/Dashboard/**/*.vue', 'Staff/Forum/Approvals/**/*.vue', 'Staff/ModerationCases/**/*.vue', 'Staff/ReportAppeals/**/*.vue']],
  ['admin.ts', ['Admin/ArcoDemo/**/*.vue', 'Admin/Website/**/*.vue']],
  ['website-preview.ts', ['Website/Pages/Show.vue', 'Website/Articles/Show.vue', 'WebsitePreview/DocumentFrame.vue']],
] as const

test('the umbrella entry is removed and every runtime has a positive resolver', () => {
  assert.equal(existsSync(resolve(entryRoot, 'inertia.ts')), false)
  for (const [entry, positiveGlobs] of applications) {
    const source = readFileSync(resolve(entryRoot, entry), 'utf8')
    assert.doesNotMatch(source, /!\.\.\/pages\//)
    assert.doesNotMatch(source, /\.\.\/pages\/\*\*\/\*\.vue/)
    for (const glob of positiveGlobs) assert.match(source, new RegExp(glob.replaceAll('*', '\\*')))
  }
})

test('website preview owns its shell frame exactly instead of claiming an unresolved directory', () => {
  assert.match(websitePreviewManifest, /"component_prefixes": \[\]/)
  assert.match(websitePreviewManifest, /"component_names": \["WebsitePreview\/DocumentFrame"\]/)
})

test('created application adapters resolve their nested prefix and exact-name claims', () => {
  assert.match(
    boundaryChecker,
    /const declaration = contribution\.creates_application \?\? contribution/,
  )
  assert.match(
    boundaryChecker,
    /if \(!contribution\.creates_application \|\| !contribution\.adapter_module\) continue/,
  )
  assert.match(boundaryChecker, /for \(const prefix of prefixes\)/)
  assert.match(boundaryChecker, /for \(const name of names\)/)
  assert.match(boundaryChecker, /requirePositiveResolver\(adapterSource, name, true\)/)
})

test('each entry discovers executable contributions only for its own runtime', () => {
  for (const [entry] of applications) {
    const source = readFileSync(resolve(entryRoot, entry), 'utf8')
    assert.doesNotMatch(source, /frontend-application-adapters\/\*\*\/\*\.ts/)
  }
})

test('application styles are separate roots and CE declares no Channel entry', () => {
  const styleNames = readdirSync(resolve(root, 'app/javascript/styles/applications')).sort()
  assert.deepEqual(styleNames, [
    'account.css',
    'admin.css',
    'forum.css',
    'staff.css',
    'store.css',
    'website-preview.css',
    'website.css',
  ])
  assert.equal(existsSync(resolve(entryRoot, 'channel.ts')), false)
  assert.equal(existsSync(resolve(entryRoot, 'pvp.ts')), false)
})

test('navigation and prefetch resolve route kind instead of treating all app paths as one SPA', () => {
  const navigation = readFileSync(
    resolve(root, 'app/javascript/lib/applicationNavigation.ts'),
    'utf8',
  )
  const prefetch = readFileSync(resolve(root, 'app/javascript/lib/intentPrefetch.ts'), 'utf8')
  assert.match(navigation, /match\.rule\.kind === 'inertia_page'/)
  assert.match(navigation, /window\.location\.assign/)
  assert.match(prefetch, /match\.rule\.kind !== 'inertia_page'/)
  assert.doesNotMatch(prefetch, /PREFETCHABLE_PREFIXES/)
})

test('the client registry matches the server exact-root and descendant API contract', () => {
  const clientRegistry = readFileSync(
    resolve(root, 'app/javascript/lib/frontendApplications.ts'),
    'utf8',
  )
  assert.match(clientRegistry, /function exactParentAndDescendantGlob/)
  assert.match(clientRegistry, /if \(exactParentAndDescendantGlob\(left\.pattern, right\.pattern\)\) return false/)
})

test('downstream navigation visibility is a shared fail-closed server-prop contract', () => {
  const schema = readFileSync(
    resolve(root, 'config/frontend_applications/schema.json'),
    'utf8',
  )
  const serverRegistry = readFileSync(
    resolve(root, 'app/services/frontend/application_registry.rb'),
    'utf8',
  )
  const clientRegistry = readFileSync(
    resolve(root, 'app/javascript/lib/frontendApplications.ts'),
    'utf8',
  )
  const adapters = readFileSync(
    resolve(root, 'app/javascript/lib/frontendApplicationAdapters.ts'),
    'utf8',
  )
  const shell = readFileSync(
    resolve(root, 'app/javascript/lib/applicationShell.ts'),
    'utf8',
  )

  for (const source of [schema, serverRegistry, clientRegistry, adapters]) {
    assert.match(source, /visibility_prop|visibilityProp/)
  }
  assert.match(clientRegistry, /function localeKeyValue/)
  assert.match(clientRegistry, /labelKey: localeKeyValue\(item\.label_key/)
  assert.match(clientRegistry, /labelKey: localeKeyValue\(group\.label_key/)
  assert.match(shell, /resolveShellProp\(pageProps, item\.visibilityProp\) !== true/)
  for (const layout of ['PortalLayout.vue', 'StaffLayout.vue', 'ArcoAdminLayout.vue']) {
    const source = readFileSync(resolve(root, 'app/javascript/layouts', layout), 'utf8')
    assert.match(source, /isApplicationShellNavigationItemVisible/)
  }
})

test('downstream page loaders are confined to declared repository page roots', () => {
  const schema = readFileSync(
    resolve(root, 'config/frontend_applications/schema.json'),
    'utf8',
  )
  const serverRegistry = readFileSync(
    resolve(root, 'app/services/frontend/application_registry.rb'),
    'utf8',
  )
  const clientRegistry = readFileSync(
    resolve(root, 'app/javascript/lib/frontendApplications.ts'),
    'utf8',
  )
  const adapters = readFileSync(
    resolve(root, 'app/javascript/lib/frontendApplicationAdapters.ts'),
    'utf8',
  )

  assert.match(schema, /"page_roots"/)
  assert.match(serverRegistry, /validate_page_roots!/)
  assert.match(clientRegistry, /pageRootsValue/)
  assert.match(adapters, /canonicalPagePath\(pagePath, contribution\.pageRoots\)/)
  assert.match(adapters, /app\/javascript\/pages/)
})
