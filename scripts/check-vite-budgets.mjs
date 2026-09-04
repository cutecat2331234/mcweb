import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs'
import { basename, relative, resolve } from 'node:path'
import { brotliCompressSync, gzipSync } from 'node:zlib'

const argv = process.argv.slice(2)
const reportOnly = argv.includes('--report-only')
const manifestArgument = argv.find((argument) => argument.startsWith('--manifest='))
const manifestPath = resolve(
  manifestArgument?.slice('--manifest='.length) ?? 'public/vite/.vite/manifest.json',
)
const viteSourceRoot = resolve('app/javascript')
const registryRoot = resolve('config/frontend_applications')
const contributionRoot = resolve(registryRoot, 'contributions')

if (!existsSync(manifestPath)) {
  console.error(`Vite manifest not found: ${manifestPath}`)
  process.exit(1)
}

const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'))
const outputRoot = resolve(manifestPath, '..', '..')
const baseDescriptors = readdirSync(resolve(registryRoot, 'base'))
  .filter((name) => name.endsWith('.json'))
  .sort()
  .map((name) => ({
    source: `base/${name}`,
    descriptor: JSON.parse(readFileSync(resolve(registryRoot, 'base', name), 'utf8')),
    pageRoots: ['app/javascript/pages'],
  }))
const contributionManifests = (existsSync(contributionRoot) ? readdirSync(contributionRoot) : [])
  .filter((name) => name.endsWith('.json'))
  .sort()
  .map((name) => ({
    name,
    contribution: JSON.parse(readFileSync(resolve(contributionRoot, name), 'utf8')),
  }))
const contributedDescriptors = contributionManifests
  .flatMap(({ name, contribution }) => {
    return contribution.creates_application
      ? [{
          source: `contributions/${name}`,
          descriptor: {
            ...contribution.creates_application,
            product_owner: contribution.product_owner,
            runtime_owner: contribution.runtime_owner,
          },
          pageRoots: contribution.page_roots ?? ['app/javascript/pages'],
          contribution,
        }]
      : []
  })
const descriptorById = new Map([...baseDescriptors, ...contributedDescriptors]
  .map((record) => [record.descriptor.id, record]))
const extensionDescriptors = contributionManifests.flatMap(({ name, contribution }) => {
  if (!contribution.extends_application || contribution.exclusive_renderer) return []
  const target = descriptorById.get(contribution.extends_application)
  if (!target || !contribution.budget) return []
  return [{
    source: `contributions/${name}`,
    descriptor: {
      ...target.descriptor,
      budget: contribution.budget,
    },
    pageRoots: contribution.page_roots ?? ['app/javascript/pages'],
    contribution,
  }]
})
const descriptors = [...baseDescriptors, ...contributedDescriptors, ...extensionDescriptors]
const componentRouteWitnesses = descriptors.flatMap(({ descriptor, pageRoots }) => {
  const paths = descriptor.budget?.representative_paths ?? []
  const components = descriptor.budget?.representative_components ?? []
  if (paths.length !== components.length) return []
  return paths.map((path, index) => ({
    application: descriptor.id,
    path,
    component: components[index],
    pageRoots,
  }))
})

function collectEntry(key, collectedKeys, files, entries = manifest) {
  if (!key || collectedKeys.has(key)) return
  const entry = entries[key]
  if (!entry) return

  collectedKeys.add(key)
  if (entry.file) files.add(entry.file)
  for (const file of entry.css ?? []) files.add(file)
  for (const file of entry.assets ?? []) files.add(file)
  // Route components are explicit roots below. Following every lazy edge here
  // would turn an initial-route budget into the size of the entire application.
  for (const importedKey of entry.imports ?? []) collectEntry(importedKey, collectedKeys, files, entries)
}

function repositoryManifestKey(repositoryPath, entries = manifest, sourceRoot = viteSourceRoot) {
  const expected = relative(sourceRoot, resolve(repositoryPath)).replaceAll('\\', '/')
  const matches = Object.entries(entries)
    .filter(([key, entry]) => key === expected || entry.src === expected)
    .map(([key]) => key)
  return matches.length === 1 ? matches[0] : null
}

function componentManifestKey(component, pageRoots) {
  const matches = pageRoots
    .map((pageRoot) => repositoryManifestKey(`${pageRoot}/${component}.vue`))
    .filter(Boolean)
  return matches.length === 1 ? matches[0] : null
}

function byteMetrics(files, assetRoot = outputRoot) {
  let raw = 0
  let gzip = 0
  let brotli = 0
  for (const file of files) {
    const path = resolve(assetRoot, file)
    if (!existsSync(path) || statSync(path).isDirectory()) continue
    const contents = readFileSync(path)
    raw += contents.byteLength
    gzip += gzipSync(contents, { level: 9 }).byteLength
    brotli += brotliCompressSync(contents).byteLength
  }
  return { raw, gzip, brotli }
}

function kb(bytes) {
  return Number((bytes / 1024).toFixed(1))
}

function javascriptFiles(files) {
  return new Set([...files].filter((file) => /\.(?:c|m)?js$/.test(file)))
}

function stylesheetFiles(files) {
  return new Set([...files].filter((file) => file.endsWith('.css')))
}

function findImportCycles(entries) {
  const state = new Map()
  const stack = []
  const signatures = new Set()
  const cycles = []

  function visit(key) {
    if (state.get(key) === 'visited') return
    if (state.get(key) === 'visiting') {
      const cycleStart = stack.indexOf(key)
      const cycleKeys = stack.slice(cycleStart)
      const signature = [...cycleKeys].sort().join('\0')
      if (!signatures.has(signature)) {
        signatures.add(signature)
        cycles.push(cycleKeys.map((cycleKey) => entries[cycleKey]?.file ?? cycleKey))
      }
      return
    }

    state.set(key, 'visiting')
    stack.push(key)
    for (const importedKey of entries[key]?.imports ?? []) {
      if (entries[importedKey]) visit(importedKey)
    }
    stack.pop()
    state.set(key, 'visited')
  }

  for (const key of Object.keys(entries)) visit(key)
  return cycles
}

let failed = false
const importCycles = findImportCycles(manifest)
if (importCycles.length > 0) {
  failed = true
  console.error('Static Vite import cycles detected:')
  for (const cycle of importCycles) console.error(`  ${[...cycle, cycle[0]].join(' -> ')}`)
}

const results = []
for (const { source, descriptor, pageRoots, contribution } of descriptors) {
  const paths = descriptor.budget?.representative_paths ?? []
  const components = descriptor.budget?.representative_components ?? []
  const entries = descriptor.budget?.representative_entries ?? []
  const resources = components.length > 0 ? components : entries
  if (paths.length === 0 || paths.length !== resources.length
    || (components.length > 0) === (entries.length > 0)) {
    failed = true
    console.error(`${source}: representative paths/resources are missing or misaligned`)
    continue
  }

  const entrypoint = `entrypoints/${descriptor.entrypoint}.ts`
  if (!manifest[entrypoint]) {
    failed = true
    console.error(`${source}: registry entry is absent from Vite manifest: ${entrypoint}`)
    continue
  }

  for (let index = 0; index < paths.length; index += 1) {
    let resourceKey = null
    let routePageKey = null
    if (components.length > 0) {
      resourceKey = componentManifestKey(components[index], pageRoots)
      if (!resourceKey) {
        failed = true
        console.error(
          `${source}: representative component is absent or ambiguous across Vite page roots: ${components[index]}`,
        )
        continue
      }
    } else {
      const repositoryEntry = entries[index]
      if (!existsSync(resolve(repositoryEntry))) {
        failed = true
        console.error(`${source}: representative entry source is missing: ${repositoryEntry}`)
        continue
      }
      resourceKey = repositoryManifestKey(repositoryEntry)
      // Eager adapter modules are folded into the owning entry and therefore
      // do not necessarily receive their own manifest record.
      const staticallyInlinedAdapter = contribution?.adapter_module === repositoryEntry
        && ['inertia', 'inertia_document'].includes(descriptor.runtime_kind)
      if (!resourceKey && !staticallyInlinedAdapter) {
        failed = true
        console.error(`${source}: representative entry is absent from Vite manifest: ${repositoryEntry}`)
        continue
      }
      const routeWitnesses = componentRouteWitnesses.filter((witness) => (
        witness.application === descriptor.id && witness.path === paths[index]
      ))
      if (routeWitnesses.length !== 1) {
        failed = true
        console.error(
          `${source}: representative entry route needs exactly one component budget witness: ${paths[index]}`,
        )
        continue
      }
      routePageKey = componentManifestKey(
        routeWitnesses[0].component,
        routeWitnesses[0].pageRoots,
      )
      if (!routePageKey) {
        failed = true
        console.error(
          `${source}: representative entry route component is absent from Vite manifest: ${routeWitnesses[0].component}`,
        )
        continue
      }
    }

    const keys = new Set()
    const files = new Set()
    collectEntry(entrypoint, keys, files)
    collectEntry(resourceKey, keys, files)
    collectEntry(routePageKey, keys, files)
    const javascript = byteMetrics(javascriptFiles(files))
    const stylesheets = byteMetrics(stylesheetFiles(files))
    const result = {
      application: descriptor.id,
      route: paths[index],
      representative: resources[index],
      requests: files.size,
      javascriptKb: kb(javascript.raw),
      stylesheetKb: kb(stylesheets.raw),
      gzipKb: kb(javascript.gzip + stylesheets.gzip),
      brotliKb: kb(javascript.brotli + stylesheets.brotli),
      javascriptBudgetKb: kb(descriptor.budget.max_initial_javascript_bytes),
      stylesheetBudgetKb: descriptor.budget.max_initial_stylesheet_bytes
        ? kb(descriptor.budget.max_initial_stylesheet_bytes)
        : null,
    }
    results.push(result)
    if (javascript.raw > descriptor.budget.max_initial_javascript_bytes
      || (descriptor.budget.max_initial_stylesheet_bytes
        && stylesheets.raw > descriptor.budget.max_initial_stylesheet_bytes)) {
      failed = true
    }
  }
}

for (const { name, contribution } of contributionManifests) {
  if (!contribution.exclusive_renderer || contribution.renderer_runtime_kind !== 'astro_document') continue
  const astroManifestPath = resolve(contribution.renderer_manifest_path)
  if (!existsSync(astroManifestPath)) {
    failed = true
    console.error(`contributions/${name}: Astro manifest is missing: ${astroManifestPath}`)
    continue
  }
  const astroManifest = JSON.parse(readFileSync(astroManifestPath, 'utf8'))
  const astroOutputRoot = resolve(astroManifestPath, '..', '..')
  const paths = contribution.budget?.representative_paths ?? []
  const entries = contribution.budget?.representative_entries ?? []
  if (paths.length === 0 || paths.length !== entries.length) {
    failed = true
    console.error(`contributions/${name}: Astro representative paths/entries are misaligned`)
    continue
  }
  for (let index = 0; index < paths.length; index += 1) {
    const entryKey = Object.keys(astroManifest).find((key) => (
      key === entries[index] || astroManifest[key]?.src === entries[index]
    ))
    if (!entryKey) {
      failed = true
      console.error(`contributions/${name}: Astro entry is absent from its manifest: ${entries[index]}`)
      continue
    }
    const keys = new Set()
    const files = new Set()
    collectEntry(entryKey, keys, files, astroManifest)
    const javascript = byteMetrics(
      javascriptFiles(files),
      astroOutputRoot,
    )
    const stylesheets = byteMetrics(
      stylesheetFiles(files),
      astroOutputRoot,
    )
    results.push({
      application: contribution.extends_application,
      route: paths[index],
      representative: entries[index],
      requests: files.size,
      javascriptKb: kb(javascript.raw),
      stylesheetKb: kb(stylesheets.raw),
      gzipKb: kb(javascript.gzip + stylesheets.gzip),
      brotliKb: kb(javascript.brotli + stylesheets.brotli),
      javascriptBudgetKb: kb(contribution.budget.max_initial_javascript_bytes),
      stylesheetBudgetKb: contribution.budget.max_initial_stylesheet_bytes
        ? kb(contribution.budget.max_initial_stylesheet_bytes)
        : null,
    })
    if (javascript.raw > contribution.budget.max_initial_javascript_bytes
      || (contribution.budget.max_initial_stylesheet_bytes
        && stylesheets.raw > contribution.budget.max_initial_stylesheet_bytes)) failed = true
  }
}

console.table(results)

const largest = Object.values(manifest)
  .filter((entry) => entry.file && existsSync(resolve(outputRoot, entry.file)))
  .map((entry) => ({
    file: basename(entry.file),
    gzipKb: kb(gzipSync(readFileSync(resolve(outputRoot, entry.file))).byteLength),
  }))
  .sort((left, right) => right.gzipKb - left.gzipKb)
  .slice(0, 15)

console.log('Largest generated files (gzip KB)')
console.table(largest)

if (failed && !reportOnly) {
  console.error('Frontend application performance budget exceeded.')
  process.exit(1)
}
