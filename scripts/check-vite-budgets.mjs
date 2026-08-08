import { existsSync, readFileSync, statSync } from 'node:fs'
import { resolve } from 'node:path'
import { brotliCompressSync, gzipSync } from 'node:zlib'

const argv = process.argv.slice(2)
const reportOnly = argv.includes('--report-only')
const manifestArgument = argv.find((argument) => argument.startsWith('--manifest='))
const manifestPath = resolve(
  manifestArgument?.slice('--manifest='.length) ??
    'public/vite/.vite/manifest.json',
)

if (!existsSync(manifestPath)) {
  console.error(`Vite manifest not found: ${manifestPath}`)
  process.exit(1)
}

const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'))
const outputRoot = resolve(manifestPath, '..', '..')
const entrypoint = 'entrypoints/inertia.ts'

const routeBudgets = [
  {
    name: 'website-home',
    pages: ['pages/Website/Home.vue'],
    maxRequests: 30,
    maxCompressedKb: 300,
  },
  {
    name: 'identity-session',
    pages: ['pages/Identity/Sessions/New.vue'],
    maxRequests: 25,
    maxCompressedKb: 250,
  },
  {
    name: 'forum-sections',
    pages: ['pages/Community/Sections/Index.vue'],
    maxRequests: 35,
    maxCompressedKb: 400,
  },
  {
    name: 'store-products',
    pages: ['pages/Commerce/Products/Index.vue'],
    maxRequests: 35,
    maxCompressedKb: 400,
  },
  {
    name: 'channel-main',
    pages: [
      'pages/Ee/Channels/Show.vue',
      'pages/EE/Channels/Show.vue',
      'pages/Channels/Show.vue',
    ],
    maxRequests: 45,
    maxCompressedKb: 550,
    optional: true,
  },
  {
    name: 'admin-settings',
    pages: ['pages/Admin/System/Settings/Show.vue'],
    // Arco's on-demand component CSS currently resolves to 47 small files.
    // Keep a narrow regression margin without forcing a high-risk manual chunk.
    maxRequests: 50,
    maxCompressedKb: 550,
  },
]

function collectEntry(key, collectedKeys, files) {
  if (!key || collectedKeys.has(key)) return
  const entry = manifest[key]
  if (!entry) return

  collectedKeys.add(key)
  if (entry.file) files.add(entry.file)
  for (const file of entry.css ?? []) files.add(file)
  for (const file of entry.assets ?? []) files.add(file)
  for (const importedKey of entry.imports ?? []) {
    collectEntry(importedKey, collectedKeys, files)
  }
}

function byteMetrics(files) {
  let raw = 0
  let gzip = 0
  let brotli = 0
  for (const file of files) {
    const path = resolve(outputRoot, file)
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

let failed = false
const results = []
for (const budget of routeBudgets) {
  const page = budget.pages.find((candidate) => manifest[candidate])
  if (!page) {
    if (!budget.optional) {
      failed = true
      console.error(`${budget.name}: no manifest entry (${budget.pages.join(', ')})`)
    }
    continue
  }

  const keys = new Set()
  const files = new Set()
  collectEntry(entrypoint, keys, files)
  collectEntry(page, keys, files)
  const sizes = byteMetrics(files)
  const result = {
    route: budget.name,
    page,
    requests: files.size,
    rawKb: kb(sizes.raw),
    gzipKb: kb(sizes.gzip),
    brotliKb: kb(sizes.brotli),
    requestBudget: budget.maxRequests,
    compressedBudgetKb: budget.maxCompressedKb,
  }
  results.push(result)

  if (
    result.requests > budget.maxRequests ||
    result.gzipKb > budget.maxCompressedKb
  ) {
    failed = true
  }
}

console.table(results)

const largest = Object.values(manifest)
  .filter((entry) => entry.file && existsSync(resolve(outputRoot, entry.file)))
  .map((entry) => ({
    file: entry.file,
    gzipKb: kb(gzipSync(readFileSync(resolve(outputRoot, entry.file))).byteLength),
  }))
  .sort((left, right) => right.gzipKb - left.gzipKb)
  .slice(0, 15)

console.log('Largest generated files (gzip KB)')
console.table(largest)

if (failed && !reportOnly) {
  console.error('Vite performance budget exceeded.')
  process.exit(1)
}
