import { readFileSync, readdirSync } from 'node:fs'
import { join, relative, sep } from 'node:path'
import { fileURLToPath } from 'node:url'
import { currentEdition, EDITION_RANK, loadEditionMarkers } from './lib/edition.mjs'

const docsRoot = fileURLToPath(new URL('..', import.meta.url))
const contentRoot = join(docsRoot, 'src', 'content', 'docs')
const edition = currentEdition(docsRoot)
const sectionDirectories = new Set(
  loadEditionMarkers(docsRoot).flatMap((marker) => marker.sections.map((section) => section.directory)),
)

const forbiddenPathTerms = /(backlog|roadmap|remediation|production[-_ ]contract|ownership|development[-_ ]plan|quality[-_ ]acceptance)/i
const forbiddenContentTerms = /(子代理派发|开发任务清单|后续开发清单|未实现功能路线|production readiness backlog|ownership decision)/i

function markdownFiles(root) {
  return readdirSync(root, { withFileTypes: true }).flatMap((entry) => {
    const path = join(root, entry.name)
    if (entry.isDirectory()) return markdownFiles(path)
    if (entry.isFile() && /\.mdx?$/.test(entry.name) && !entry.name.startsWith('_')) return [path]
    return []
  })
}

function frontmatter(source, path) {
  const match = source.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n/)
  if (!match) throw new Error(`Missing YAML frontmatter: ${path}`)
  return match[1]
}

function scalar(yaml, key, path) {
  const match = yaml.match(new RegExp(`^${key}:\\s*(.+?)\\s*$`, 'm'))
  if (!match) throw new Error(`Missing ${key} frontmatter: ${path}`)
  return match[1].replace(/^['"]|['"]$/g, '')
}

const files = markdownFiles(contentRoot)
if (!files.length) throw new Error('The documentation site has no Markdown or MDX content')

for (const path of files) {
  const local = relative(contentRoot, path).split(sep).join('/')
  const source = readFileSync(path, 'utf8')
  const yaml = frontmatter(source, local)
  const pageEdition = scalar(yaml, 'edition', local)
  const localized = local.startsWith('en/') ? local.slice(3) : local
  const topLevel = localized.split('/')[0]

  scalar(yaml, 'title', local)
  scalar(yaml, 'description', local)
  if (!/^audience:\s*$/m.test(yaml) || !/^\s{2}-\s+\S+/m.test(yaml)) {
    throw new Error(`Missing audience list frontmatter: ${local}`)
  }
  if (!EDITION_RANK[pageEdition]) throw new Error(`Unknown edition ${pageEdition}: ${local}`)
  if (EDITION_RANK[pageEdition] > edition.rank) {
    throw new Error(`${edition.id.toUpperCase()} documentation leaks ${pageEdition.toUpperCase()} content: ${local}`)
  }
  if (forbiddenPathTerms.test(local)) throw new Error(`Internal-target path is not allowed in formal docs: ${local}`)
  if (forbiddenContentTerms.test(source)) throw new Error(`Internal-target copy is not allowed in formal docs: ${local}`)
  if (localized !== 'index.md' && !sectionDirectories.has(topLevel)) {
    throw new Error(`Documentation page is outside an edition-owned section: ${local}`)
  }
}

for (const required of ['index.md', 'getting-started/edition-and-language.md', 'en/index.md', 'en/getting-started/edition-and-language.md']) {
  if (!files.some((path) => relative(contentRoot, path).split(sep).join('/') === required)) {
    throw new Error(`Missing required locale/edition page: ${required}`)
  }
}

for (const path of files.filter((entry) => relative(contentRoot, entry).split(sep).join('/').startsWith('en/'))) {
  const local = relative(contentRoot, path).split(sep).join('/')
  const rootPeer = local.slice(3)
  if (!files.some((entry) => relative(contentRoot, entry).split(sep).join('/') === rootPeer)) {
    throw new Error(`English page has no Simplified Chinese source page: ${local}`)
  }
}

process.stdout.write(`Documentation content check passed for ${edition.id.toUpperCase()} (${files.length} pages).\n`)
