import { readFileSync, readdirSync, writeFileSync } from 'node:fs'
import { extname, join, relative, resolve } from 'node:path'
import process from 'node:process'
import { fileURLToPath } from 'node:url'

const DEFAULT_SCAN_DIRECTORIES = [
  'app/javascript/components',
  'app/javascript/layouts',
  'app/javascript/pages',
  'app/controllers',
  'app/helpers',
  'app/jobs',
  'app/mailers',
  'app/models',
  'app/services',
]
const SCAN_DIRECTORY_PREFIX = '--scan-directory='

const EXCLUDED_SEGMENTS = new Set([
  '__fixtures__',
  '__snapshots__',
  'locales',
  'vendor',
])

const USER_FACING_ATTRIBUTES = new Set([
  'alt',
  'aria-description',
  'aria-label',
  'cancel-text',
  'description',
  'empty-text',
  'help',
  'label',
  'loading-text',
  'ok-text',
  'placeholder',
  'subtitle',
  'title',
])

const TECHNICAL_TERMS = new Set([
  'api',
  'aria',
  'aws',
  'cpu',
  'csv',
  'css',
  'dc',
  'dns',
  'dom',
  'gb',
  'github',
  'html',
  'http',
  'https',
  'id',
  'ip',
  'json',
  'jwt',
  'kb',
  'mb',
  'mcweb',
  'mime',
  'oauth',
  'openid',
  'pdf',
  'postgresql',
  'redis',
  's3',
  'sdk',
  'sidekiq',
  'smtp',
  'sql',
  'ssh',
  'ssl',
  'tcp',
  'tls',
  'totp',
  'ttl',
  'ui',
  'unauthorized',
  'unprocessable',
  'url',
  'uuid',
  'webhook',
  'xml',
  'error',
])

const BASELINE_CATEGORIES = new Set([
  'development-demo',
  'historical-compatibility',
  'proper-name',
  'technical-token',
])

function lineNumberAt(source, offset) {
  return source.slice(0, offset).split('\n').length
}

function normalizeCopy(value) {
  return value
    .replace(/\{\{[\s\S]*?\}\}/g, ' ')
    .replace(/#\{[\s\S]*?\}/g, ' ')
    .replace(/&(?:[A-Za-z]+|#\d+|#x[\dA-Fa-f]+);/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
}

export function looksLikeTechnicalIdentifier(value) {
  const text = normalizeCopy(value)
  if (!text) return true
  if (/^[\d\s.,:;!?()[\]{}+\-–—/%|•·'"`~<>*=\\]+$/.test(text)) return true
  if (/^#[\dA-Fa-f]{3,8}$/.test(text)) return true
  if (/^[\dA-Fa-f]{8}-[\dA-Fa-f]{4}-[1-5][\dA-Fa-f]{3}-[89ABab][\dA-Fa-f]{3}-[\dA-Fa-f]{12}$/.test(text)) {
    return true
  }
  if (/^(?:https?:\/\/|mailto:|tel:|\/|\.\/|\.\.\/)/i.test(text)) return true
  if (/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(text)) return true
  if (/^[a-z][A-Za-z0-9_-]*(?:[.:/_-][A-Za-z0-9_-]+)+$/.test(text)) return true
  if (/^[A-Z0-9_.:/-]{2,}$/.test(text)) return true
  if (/^(?:GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)\s+\S+$/.test(text)) return true
  if (/^(?:application|audio|font|image|multipart|text|video)\/[\w.+-]+$/i.test(text)) return true
  if (/^[A-Fa-f0-9]{16,}$/.test(text)) return true
  if (/^(?:\{.*\}|\[.*\])$/.test(text)) return true
  if (/^[%A-Za-z0-9_.:/-]+(?:,[%A-Za-z0-9_.:/-]+)+$/.test(text)) return true
  if (/^[a-z0-9_-]+\.(?:css|csv|gif|html|jpeg|jpg|js|json|mjs|pdf|png|rb|svg|ts|tsx|txt|vue|xml|yml|yaml)$/i.test(text)) {
    return true
  }
  if (TECHNICAL_TERMS.has(text.toLowerCase())) return true
  if (text.length === 1 && /^[A-Za-z]$/.test(text)) return true
  return false
}

function looksLikeUserCopy(value) {
  const text = normalizeCopy(value)
  if (!text || looksLikeTechnicalIdentifier(text)) return false
  return /[\p{L}]/u.test(text)
}

function openingTags(source) {
  const tags = []
  let cursor = 0

  while (cursor < source.length) {
    const start = source.indexOf('<', cursor)
    if (start === -1) break
    const tagName = source.slice(start + 1).match(/^[A-Za-z][\w:-]*/)
    if (!tagName) {
      cursor = start + 1
      continue
    }

    let quote = null
    let end = start + tagName[0].length + 1
    for (; end < source.length; end += 1) {
      const character = source[end]
      if (quote) {
        if (character === quote && source[end - 1] !== '\\') quote = null
      } else if (character === '"' || character === "'") {
        quote = character
      } else if (character === '>') {
        tags.push({ source: source.slice(start, end + 1), offset: start })
        break
      }
    }
    cursor = end + 1
  }

  return tags
}

function textNodes(source) {
  const nodes = []
  let cursor = 0

  while (cursor < source.length) {
    const start = source.indexOf('<', cursor)
    if (start === -1) break

    let quote = null
    let end = start + 1
    for (; end < source.length; end += 1) {
      const character = source[end]
      if (quote) {
        if (character === quote && source[end - 1] !== '\\') quote = null
      } else if (character === '"' || character === "'") {
        quote = character
      } else if (character === '>') {
        break
      }
    }

    if (end >= source.length) break
    const next = source.indexOf('<', end + 1)
    const textEnd = next === -1 ? source.length : next
    const value = source.slice(end + 1, textEnd)
    if (value.trim()) nodes.push({ value, offset: end + 1 })
    cursor = textEnd
  }

  return nodes
}

function inlineAllowance(source, line) {
  if (line <= 1) return null
  const previousLine = source.split('\n')[line - 2] || ''
  const match = previousLine.match(/copylint:\s*allow-next-line\s*--\s*(.{8,})\s*$/)
  return match ? match[1].trim() : null
}

function finding({ file, kind, text, source, offset }) {
  const line = lineNumberAt(source, offset)
  return {
    file,
    kind,
    line,
    text: normalizeCopy(text),
    inlineReason: inlineAllowance(source, line),
  }
}

export function scanVueSource(source, file = 'component.vue') {
  const templateMatch = source.match(/<template(?:\s[^>]*)?>([\s\S]*?)<\/template>/i)
  if (!templateMatch) return []

  const templateOffset = templateMatch.index + templateMatch[0].indexOf(templateMatch[1])
  const template = templateMatch[1]
    .replace(/<!--[\s\S]*?-->/g, (value) => ' '.repeat(value.length))
    .replace(/<(?:code|pre|script|style|svg)\b[\s\S]*?<\/(?:code|pre|script|style|svg)>/gi, (value) => (
      ' '.repeat(value.length)
    ))
  const findings = []

  for (const node of textNodes(template)) {
    if (!looksLikeUserCopy(node.value)) continue
    findings.push(finding({
      file,
      kind: 'vue-text',
      text: node.value,
      source,
      offset: templateOffset + node.offset,
    }))
  }

  for (const tag of openingTags(template)) {
    const attributePattern = /(?:^|\s)(?!:|v-bind:)([A-Za-z][\w:-]*)\s*=\s*(["'])([\s\S]*?)\2/g
    let match
    while ((match = attributePattern.exec(tag.source)) !== null) {
      const attribute = match[1].toLowerCase()
      if (!USER_FACING_ATTRIBUTES.has(attribute) || !looksLikeUserCopy(match[3])) continue
      const valueOffset = tag.offset + match.index + match[0].indexOf(match[3])
      findings.push(finding({
        file,
        kind: `vue-attribute:${attribute}`,
        text: match[3],
        source,
        offset: templateOffset + valueOffset,
      }))
    }
  }

  return findings.filter((entry) => !entry.inlineReason)
}

function rubyPatternFindings(source, file, pattern, kind, valueIndex = 2) {
  const findings = []
  let match
  while ((match = pattern.exec(source)) !== null) {
    const value = match[valueIndex]
    if (!looksLikeUserCopy(value)) continue
    const valueOffset = match.index + match[0].indexOf(value)
    findings.push(finding({ file, kind, text: value, source, offset: valueOffset }))
  }
  return findings
}

export function scanRubySource(source, file = 'service.rb') {
  const findings = [
    ...rubyPatternFindings(
      source,
      file,
      /\b(?:alert|description|error|help|label|message|notice|subtitle|title):\s*(["'])(.*?)\1/g,
      'ruby-user-keyword',
    ),
    ...rubyPatternFindings(
      source,
      file,
      /\berrors\.add\(\s*[^,\n]+,\s*(["'])(.*?)\1/g,
      'ruby-validation',
    ),
    ...rubyPatternFindings(
      source,
      file,
      /\bflash\[[^\]]+\]\s*=\s*(["'])(.*?)\1/g,
      'ruby-flash',
    ),
    ...rubyPatternFindings(
      source,
      file,
      /\brender\s+(?:html|plain):\s*(["'])(.*?)\1/g,
      'ruby-rendered-copy',
    ),
  ]

  return findings.filter((entry) => !entry.inlineReason)
}

function walk(directory) {
  const files = []
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    if (EXCLUDED_SEGMENTS.has(entry.name)) continue
    const absolute = join(directory, entry.name)
    if (entry.isDirectory()) files.push(...walk(absolute))
    else if (entry.isFile() && ['.rb', '.vue'].includes(extname(entry.name))) files.push(absolute)
  }
  return files
}

export function validateAllowlist(document) {
  if (!document || document.version !== 1 || !Array.isArray(document.entries)) {
    throw new Error('copy allowlist must be an object with version=1 and an entries array')
  }

  const keys = new Set()
  for (const [index, entry] of document.entries.entries()) {
    for (const key of ['file', 'kind', 'text', 'reason']) {
      if (typeof entry?.[key] !== 'string' || !entry[key].trim()) {
        throw new Error(`copy allowlist entry ${index} requires a non-empty ${key}`)
      }
    }
    if (entry.reason.trim().length < 8) {
      throw new Error(`copy allowlist entry ${index} reason must contain at least 8 characters`)
    }
    const key = allowlistKey(entry)
    if (keys.has(key)) throw new Error(`duplicate copy allowlist entry: ${key}`)
    keys.add(key)
  }

  return document
}

function allowlistKey(entry) {
  return `${entry.file}\0${entry.kind}\0${entry.text}`
}

export function applyAllowlist(findings, document) {
  const allowlist = validateAllowlist(document)
  const findingKeys = new Set(findings.map(allowlistKey))
  const allowedKeys = new Set(allowlist.entries.map(allowlistKey))

  return {
    violations: findings.filter((entry) => !allowedKeys.has(allowlistKey(entry))),
    stale: allowlist.entries.filter((entry) => !findingKeys.has(allowlistKey(entry))),
  }
}

export function validateBaseline(document) {
  if (!document || document.version !== 2 || !Array.isArray(document.entries)) {
    throw new Error('copy baseline must be an object with version=2 and an entries array')
  }

  const keys = new Set()
  for (const [index, entry] of document.entries.entries()) {
    for (const key of ['file', 'kind', 'text', 'category', 'reason']) {
      if (typeof entry?.[key] !== 'string' || !entry[key].trim()) {
        throw new Error(`copy baseline entry ${index} requires a non-empty ${key}`)
      }
    }
    if (!BASELINE_CATEGORIES.has(entry.category)) {
      throw new Error(`copy baseline entry ${index} has unsupported category ${entry.category}`)
    }
    if (entry.reason.trim().length < 16) {
      throw new Error(`copy baseline entry ${index} reason must contain at least 16 characters`)
    }
    if (
      entry.category === 'development-demo' &&
      !/(?:demo|developer_scenario)/i.test(entry.file)
    ) {
      throw new Error(
        `copy baseline entry ${index} development-demo must live in a gated demo source`,
      )
    }
    if (
      entry.category === 'technical-token' &&
      !looksLikeTechnicalIdentifier(entry.text)
    ) {
      throw new Error(
        `copy baseline entry ${index} technical-token is not a technical identifier`,
      )
    }
    if (entry.category === 'historical-compatibility') {
      if (typeof entry.trackingIssue !== 'string' || entry.trackingIssue.trim().length < 4) {
        throw new Error(
          `copy baseline entry ${index} historical-compatibility requires trackingIssue`,
        )
      }
      if (
        typeof entry.reviewBy !== 'string' ||
        !/^\d{4}-\d{2}-\d{2}$/.test(entry.reviewBy) ||
        Number.isNaN(Date.parse(`${entry.reviewBy}T00:00:00Z`))
      ) {
        throw new Error(
          `copy baseline entry ${index} historical-compatibility requires reviewBy`,
        )
      }
      const reviewDeadline = Date.parse(`${entry.reviewBy}T23:59:59Z`)
      if (reviewDeadline < Date.now()) {
        throw new Error(
          `copy baseline entry ${index} historical-compatibility reviewBy has expired`,
        )
      }
    }
    const key = allowlistKey(entry)
    if (keys.has(key)) throw new Error(`duplicate copy baseline entry: ${key}`)
    keys.add(key)
  }
  return document
}

export function applyBaseline(findings, document) {
  const baseline = validateBaseline(document)
  const findingKeys = new Set(findings.map(allowlistKey))
  const baselineKeys = new Set(baseline.entries.map(allowlistKey))

  return {
    baselineCount: baseline.entries.length,
    categoryCounts: baseline.entries.reduce((counts, entry) => {
      counts[entry.category] = (counts[entry.category] || 0) + 1
      return counts
    }, {}),
    violations: findings.filter((entry) => !baselineKeys.has(allowlistKey(entry))),
    stale: baseline.entries.filter((entry) => !findingKeys.has(allowlistKey(entry))),
  }
}

export function parseScanDirectories(args = []) {
  return [...new Set(args
    .filter((argument) => argument.startsWith(SCAN_DIRECTORY_PREFIX))
    .map((argument) => argument.slice(SCAN_DIRECTORY_PREFIX.length).replaceAll('\\', '/'))
    .map((directory) => {
      if (
        !directory
        || directory.startsWith('/')
        || /^[A-Za-z]:/.test(directory)
        || directory.split('/').includes('..')
        || !/^[A-Za-z0-9._/-]+$/.test(directory)
      ) {
        throw new Error(`unsafe scan directory: ${JSON.stringify(directory)}`)
      }
      return directory.replace(/^\.\/+/, '').replace(/\/+$/, '')
    }))]
}

export function scanProject(root = process.cwd(), extraDirectories = []) {
  const resolvedRoot = resolve(root)
  const directories = [...new Set([
    ...DEFAULT_SCAN_DIRECTORIES,
    ...extraDirectories,
  ])]
  const files = directories.flatMap((directory) => {
    const absolute = join(resolvedRoot, directory)
    try {
      return walk(absolute)
    } catch (error) {
      if (error && error.code === 'ENOENT') return []
      throw error
    }
  })

  return files.flatMap((absolute) => {
    const file = relative(resolvedRoot, absolute).replaceAll('\\', '/')
    const source = readFileSync(absolute, 'utf8')
    if (extname(absolute) === '.vue') return scanVueSource(source, file)
    if (extname(absolute) === '.rb') return scanRubySource(source, file)
    return []
  })
}

function report(title, entries) {
  if (!entries.length) return
  process.stderr.write(`${title}:\n`)
  for (const entry of entries) {
    process.stderr.write(
      `  ${entry.file}${entry.line ? `:${entry.line}` : ''} [${entry.kind}] ${JSON.stringify(entry.text)}\n`,
    )
  }
}

function main() {
  const root = resolve(process.cwd())
  const allowlistPath = join(root, 'config/user-facing-copy-allowlist.json')
  const baselinePath = join(root, 'config/user-facing-copy-baseline.json')
  const allowlist = JSON.parse(readFileSync(allowlistPath, 'utf8'))
  const extraDirectories = parseScanDirectories(process.argv.slice(2))
  const allowlistResult = applyAllowlist(scanProject(root, extraDirectories), allowlist)

  if (process.argv.includes('--write-baseline')) {
    const entries = [...new Map(
      allowlistResult.violations
        .map(({ file, kind, text }) => ({ file, kind, text }))
        .map((entry) => [allowlistKey(entry), entry]),
    ).values()]
      .sort((left, right) => allowlistKey(left).localeCompare(allowlistKey(right)))
    writeFileSync(
      baselinePath,
      `${JSON.stringify({
        version: 2,
        description: 'Review required: classify every exception and add a concrete reason before this baseline can pass CI.',
        entries: entries.map((entry) => ({
          ...entry,
          category: 'unreviewed',
          reason: 'REVIEW REQUIRED before merge',
        })),
      }, null, 2)}\n`,
      'utf8',
    )
    process.stdout.write(
      `Wrote ${entries.length} unreviewed baseline candidates to ${baselinePath}; classify them before CI can pass.\n`,
    )
    return
  }

  const baseline = JSON.parse(readFileSync(baselinePath, 'utf8'))
  const result = applyBaseline(allowlistResult.violations, baseline)

  report('Hard-coded user-facing copy', result.violations)
  report('Stale copy baseline entries', result.stale)
  report('Stale copy allowlist entries', allowlistResult.stale)

  if (result.violations.length || result.stale.length || allowlistResult.stale.length) {
    process.stderr.write(
      'Move copy to I18N, or add an exact reviewed exception with a concrete reason.\n',
    )
    process.exitCode = 1
    return
  }

  const categorySummary = Object.entries(result.categoryCounts)
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([category, count]) => `${category}=${count}`)
    .join(', ')
  process.stdout.write(
    `User-facing copy check passed (no production copy debt; ${result.baselineCount} reviewed exceptions: ${categorySummary || 'none'}).\n`,
  )
}

if (process.argv[1] && resolve(process.argv[1]) === resolve(fileURLToPath(import.meta.url))) {
  main()
}
