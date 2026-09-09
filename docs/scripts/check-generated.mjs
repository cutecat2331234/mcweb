import { existsSync, readFileSync, readdirSync } from 'node:fs'
import { extname, join, normalize, relative, sep } from 'node:path'
import { fileURLToPath } from 'node:url'
import { currentEdition } from './lib/edition.mjs'

const docsRoot = fileURLToPath(new URL('..', import.meta.url))
const distRoot = join(docsRoot, 'dist')
const edition = currentEdition(docsRoot)

function filesBelow(root) {
  return readdirSync(root, { withFileTypes: true }).flatMap((entry) => {
    const path = join(root, entry.name)
    return entry.isDirectory() ? filesBelow(path) : [path]
  })
}

function routeFor(path) {
  const local = relative(distRoot, path).split(sep).join('/')
  if (local === 'index.html') return '/docs/'
  if (local.endsWith('/index.html')) return `/docs/${local.slice(0, -10)}`
  return `/docs/${local}`
}

function targetPath(urlPath) {
  let local = decodeURIComponent(urlPath).replace(/^\/docs\/?/, '')
  if (!local || local.endsWith('/')) local += 'index.html'
  else if (!extname(local)) local += '/index.html'
  return normalize(join(distRoot, local))
}

if (!existsSync(distRoot)) throw new Error('Documentation dist directory does not exist')
const htmlFiles = filesBelow(distRoot).filter((path) => path.endsWith('.html'))
const htmlByPath = new Map(htmlFiles.map((path) => [normalize(path), readFileSync(path, 'utf8')]))

for (const required of ['index.html', 'en/index.html', '404.html']) {
  if (!existsSync(join(distRoot, required))) throw new Error(`Missing generated page: ${required}`)
}
if (!existsSync(join(distRoot, 'pagefind', 'pagefind.js'))) throw new Error('Missing Pagefind search runtime')
if (!filesBelow(join(distRoot, 'pagefind')).some((path) => /pagefind.*\.(pf_index|json)$/.test(path))) {
  throw new Error('Missing Pagefind search index')
}

for (const [path, html] of htmlByPath) {
  const route = routeFor(path)
  if (!/<meta[^>]+name=["']mcweb-edition["'][^>]+content=["'][^"']+["']/i.test(html)) {
    throw new Error(`Missing edition metadata: ${route}`)
  }
  const headingCount = [...html.matchAll(/<h1\b/gi)].length
  if (headingCount !== 1) throw new Error(`Expected exactly one h1 on ${route}; found ${headingCount}`)
  for (const match of html.matchAll(/<a\b[^>]*\bhref=["']([^"']+)["']/gi)) {
    const href = match[1]
    if (/^(?:https?:|mailto:|tel:|javascript:)/i.test(href)) continue
    const parsed = new URL(href, `https://mcweb.invalid${route}`)
    if (!parsed.pathname.startsWith('/docs/')) continue
    const target = targetPath(parsed.pathname)
    const targetHtml = htmlByPath.get(target)
    if (!targetHtml) throw new Error(`Broken link from ${route} to ${href}`)
    if (parsed.hash) {
      const id = decodeURIComponent(parsed.hash.slice(1))
      const escaped = id.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
      if (!new RegExp(`\\bid=["']${escaped}["']`).test(targetHtml)) {
        throw new Error(`Broken heading anchor from ${route} to ${href}`)
      }
    }
  }
}

const rootHtml = readFileSync(join(distRoot, 'index.html'), 'utf8')
const englishHtml = readFileSync(join(distRoot, 'en', 'index.html'), 'utf8')
if (!/<html[^>]+lang=["']zh-CN["']/i.test(rootHtml)) throw new Error('Root documentation locale is not zh-CN')
if (!/<html[^>]+lang=["']en["']/i.test(englishHtml)) throw new Error('English documentation locale is not en')

process.stdout.write(`Generated documentation check passed for ${edition.id.toUpperCase()} (${htmlFiles.length} HTML pages).\n`)
