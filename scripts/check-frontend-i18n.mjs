import fs from 'node:fs'
import path from 'node:path'
import process from 'node:process'

const ROOT = process.cwd()
const LOCALES = {
  en: path.join(ROOT, 'app/javascript/locales/en.ts'),
  'zh-CN': path.join(ROOT, 'app/javascript/locales/zh-CN.ts'),
}

function fail(message) {
  throw new Error(message)
}

function flattenObject(value, locale, prefix = '', result = new Map()) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    fail(`${locale} locale must contain nested objects of message strings`)
  }

  for (const [key, entry] of Object.entries(value)) {
    const fullKey = prefix ? `${prefix}.${key}` : key
    if (entry && typeof entry === 'object' && !Array.isArray(entry)) {
      flattenObject(entry, locale, fullKey, result)
    } else {
      if (typeof entry !== 'string') {
        fail(`${locale} locale entry ${fullKey} must be a string`)
      }
      result.set(fullKey, entry)
    }
  }

  return result
}

async function readLocale(locale, filename) {
  const source = fs.readFileSync(filename, 'utf8').replace(/\}\s+as const\s*$/, '}')
  const encoded = Buffer.from(source, 'utf8').toString('base64')
  const loaded = await import(`data:text/javascript;base64,${encoded}#${encodeURIComponent(locale)}`)
  return flattenObject(loaded.default, locale)
}

function placeholders(value) {
  if (value === null) return []

  return [...value.matchAll(/\{([A-Za-z_][A-Za-z0-9_.-]*)\}/g)]
    .map((match) => match[1])
    .sort()
}

function difference(left, right) {
  return [...left.keys()].filter((key) => !right.has(key)).sort()
}

function reportList(label, values) {
  if (!values.length) return

  process.stderr.write(`${label}:\n`)
  values.forEach((value) => process.stderr.write(`  - ${value}\n`))
}

try {
  const dictionaries = Object.fromEntries(
    await Promise.all(
      Object.entries(LOCALES).map(async ([locale, filename]) => [
        locale,
        await readLocale(locale, filename),
      ]),
    ),
  )
  const english = dictionaries.en
  const chinese = dictionaries['zh-CN']
  const missingChinese = difference(english, chinese)
  const missingEnglish = difference(chinese, english)
  const placeholderMismatches = [...english.keys()]
    .filter((key) => chinese.has(key))
    .filter((key) => placeholders(english.get(key)).join('\0') !== placeholders(chinese.get(key)).join('\0'))
    .sort()

  reportList('Missing from zh-CN', missingChinese)
  reportList('Missing from en', missingEnglish)
  reportList('Interpolation placeholders differ', placeholderMismatches)

  if (missingChinese.length || missingEnglish.length || placeholderMismatches.length) {
    process.exitCode = 1
  } else {
    process.stdout.write(`Frontend locale parity passed (${english.size} keys).\n`)
  }
} catch (error) {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`)
  process.exitCode = 1
}
