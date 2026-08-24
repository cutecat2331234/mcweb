import { existsSync, readFileSync, readdirSync } from 'node:fs'
import { dirname, relative, resolve } from 'node:path'

const root = resolve('.')
const registryRoot = resolve(root, 'config/frontend_applications')
const pageRoot = resolve(root, 'app/javascript/pages')
const entryRoot = resolve(root, 'app/javascript/entrypoints')

function jsonFiles(directory) {
  if (!existsSync(directory)) return []
  return readdirSync(directory)
    .filter((name) => name.endsWith('.json'))
    .sort()
    .map((name) => ({
      source: relative(root, resolve(directory, name)).replaceAll('\\', '/'),
      value: JSON.parse(readFileSync(resolve(directory, name), 'utf8')),
    }))
}

function walk(directory) {
  if (!existsSync(directory)) return []
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const path = resolve(directory, entry.name)
    return entry.isDirectory() ? walk(path) : [path]
  })
}

const applications = new Map(jsonFiles(resolve(registryRoot, 'base')).map(({ source, value }) => [
  value.id,
  {
    ...value,
    source,
    contributions: [],
  },
]))
const contributions = jsonFiles(resolve(registryRoot, 'contributions'))

for (const { source, value } of contributions) {
  if (!value.creates_application) continue
  const descriptor = {
    ...value.creates_application,
    product_owner: value.product_owner,
    runtime_owner: value.runtime_owner,
    source,
    contributions: [{ ...value, source }],
  }
  if (applications.has(descriptor.id)) throw new Error(`${source}: duplicate application ${descriptor.id}`)
  applications.set(descriptor.id, descriptor)
}

for (const { source, value } of contributions) {
  if (!value.extends_application) continue
  const descriptor = applications.get(value.extends_application)
  if (!descriptor) throw new Error(`${source}: unknown application ${value.extends_application}`)
  descriptor.contributions.push({ ...value, source })
  if (value.renderer_adapter && value.exclusive_renderer) {
    descriptor.runtime_kind = value.renderer_runtime_kind
    descriptor.entrypoint = value.renderer_entrypoint
    descriptor.styles = value.styles
    descriptor.locales = value.locales
    descriptor.error_boundary = value.error_boundary
    descriptor.budget = value.budget
    descriptor.renderer_manifest_path = value.renderer_manifest_path
  } else {
    descriptor.component_prefixes.push(...(value.component_prefixes ?? []))
    descriptor.component_names.push(...(value.component_names ?? []))
    descriptor.styles.push(...(value.styles ?? []))
    descriptor.locales.push(...(value.locales ?? []))
  }
}

if (existsSync(resolve(entryRoot, 'inertia.ts'))) {
  throw new Error('The removed umbrella entrypoints/inertia.ts contract has returned')
}

const claims = [...applications.values()].flatMap((descriptor) => [
  ...descriptor.component_prefixes.map((prefix) => ({
    prefix,
    exact: false,
    application: descriptor.id,
    source: descriptor.source,
  })),
  ...descriptor.component_names.map((prefix) => ({
    prefix,
    exact: true,
    application: descriptor.id,
    source: descriptor.source,
  })),
])

const pages = walk(pageRoot)
  .filter((path) => path.endsWith('.vue'))
  .map((path) => relative(pageRoot, path).replaceAll('\\', '/').replace(/\.vue$/, ''))
const unowned = []
const ambiguous = []
for (const page of pages) {
  const owners = claims
    .filter((claim) => (claim.exact ? page === claim.prefix : page.startsWith(claim.prefix)))
    .sort((left, right) => right.prefix.length - left.prefix.length)
  if (owners.length === 0) unowned.push(page)
  if (owners.length > 1 && owners[0].prefix.length === owners[1].prefix.length) {
    ambiguous.push(`${page}: ${owners[0].source}, ${owners[1].source}`)
  }
}
if (unowned.length || ambiguous.length) {
  throw new Error(`Page ownership failed: unowned=${unowned.join(', ')} ambiguous=${ambiguous.join(', ')}`)
}

function requirePositiveResolver(source, prefix, exact = false) {
  const pageExpression = exact ? `${prefix}.vue` : `${prefix}**/*.vue`
  if (!source.includes(pageExpression)) {
    throw new Error(`Missing positive page resolver ${pageExpression}`)
  }
}

function adapterPageClaims(contribution) {
  const declaration = contribution.creates_application ?? contribution
  return {
    prefixes: declaration.component_prefixes ?? [],
    names: declaration.component_names ?? [],
  }
}

for (const descriptor of applications.values()) {
  if (descriptor.runtime_kind === 'astro_document') {
    const manifest = resolve(root, descriptor.renderer_manifest_path)
    if (!existsSync(manifest)) throw new Error(`${descriptor.id}: Astro manifest is missing: ${manifest}`)
    const sourceRoot = resolve(root, dirname(dirname(dirname(descriptor.renderer_manifest_path))))
    for (const entry of descriptor.budget.representative_entries ?? []) {
      const sourceEntry = resolve(sourceRoot, entry)
      if (!existsSync(sourceEntry)) throw new Error(`${descriptor.id}: Astro entry is missing: ${sourceEntry}`)
    }
    for (const file of walk(resolve(sourceRoot, 'src'))) {
      if (!/\.(?:astro|[cm]?[jt]sx?|vue)$/.test(file)) continue
      if (readFileSync(file, 'utf8').includes('@mcweb/ui')) {
        throw new Error(`${descriptor.id}: Astro Website must not import the APP UI library: ${file}`)
      }
    }
    continue
  }

  const entryPath = resolve(entryRoot, `${descriptor.entrypoint}.ts`)
  if (!existsSync(entryPath)) throw new Error(`${descriptor.id}: entry is missing: ${entryPath}`)
  const source = readFileSync(entryPath, 'utf8')
  if (/!\.\.\/pages\//.test(source) || source.includes("'../pages/**/*.vue'")) {
    throw new Error(`${descriptor.id}: entry uses a negative or umbrella page glob`)
  }
  if (!source.includes(`applicationId: '${descriptor.id}'`)
    || !source.includes(`@/styles/applications/${descriptor.id.replaceAll('_', '-')}.css`)) {
    throw new Error(`${descriptor.id}: entry identity or style root does not match its manifest`)
  }

  const baseContributionPrefixes = new Set(descriptor.contributions
    .filter((contribution) => contribution.extends_application)
    .flatMap((contribution) => contribution.component_prefixes ?? []))
  const baseContributionNames = new Set(descriptor.contributions
    .filter((contribution) => contribution.extends_application)
    .flatMap((contribution) => contribution.component_names ?? []))
  for (const contribution of descriptor.contributions) {
    if (!contribution.creates_application || !contribution.adapter_module) continue
    const { prefixes, names } = adapterPageClaims(contribution)
    for (const prefix of prefixes) baseContributionPrefixes.add(prefix)
    for (const name of names) baseContributionNames.add(name)
  }
  for (const prefix of descriptor.component_prefixes) {
    if (!baseContributionPrefixes.has(prefix)) requirePositiveResolver(source, prefix)
  }
  for (const name of descriptor.component_names) {
    if (!baseContributionNames.has(name)) requirePositiveResolver(source, name, true)
  }

  for (const contribution of descriptor.contributions) {
    if (!contribution.adapter_module) continue
    const adapterPath = resolve(root, contribution.adapter_module)
    if (!existsSync(adapterPath)) throw new Error(`${contribution.source}: adapter is missing: ${adapterPath}`)
    const adapterSource = readFileSync(adapterPath, 'utf8')
    if (!adapterSource.includes(`applicationId: '${descriptor.id}'`)
      || !adapterSource.includes(`contributionId: '${contribution.contribution_id}'`)) {
      throw new Error(`${contribution.source}: adapter identity is not literal and exact`)
    }
    const { prefixes, names } = adapterPageClaims(contribution)
    for (const prefix of prefixes) {
      requirePositiveResolver(adapterSource, prefix)
    }
    for (const name of names) {
      requirePositiveResolver(adapterSource, name, true)
    }
  }
}

for (const domain of walk(resolve(root, 'app/javascript/locales/domains'))) {
  if (!domain.endsWith('.ts')) continue
  const source = readFileSync(domain, 'utf8')
  if (/from ['"]\.\.\/\.\.\/(?:en|zh-CN)['"]/.test(source)) {
    throw new Error(`Locale domain imports the monolithic catalogue: ${domain}`)
  }
}

console.log(`Frontend application boundaries cover ${pages.length} pages across ${applications.size} applications.`)
