import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { resolve } from 'node:path'
import ts from 'typescript'

const sourceRoot = resolve('app/javascript/locales')
const outputRoot = resolve(sourceRoot, 'domains')
const locales = ['en', 'zh-CN']
const domainKeys = {
  core: ['common', 'locale', 'components'],
  website: ['website'],
  forum: ['nav', 'portal', 'breadcrumb', 'shortcuts', 'forum', 'userProfile', 'checkIn'],
  store: ['nav', 'portal', 'breadcrumb', 'commerce', 'payments'],
  account: ['nav', 'portal', 'breadcrumb', 'accountCenter', 'accountNotifications', 'auth', 'identity', 'minecraft'],
  staff: ['nav', 'staffWorkspace'],
  admin: ['admin', 'adminMinecraft', 'adminForum', 'commerce', 'forum', 'identity', 'minecraft', 'payments', 'website'],
}

async function loadCatalog(locale) {
  const source = readFileSync(resolve(sourceRoot, `${locale}.ts`), 'utf8')
  const javascript = ts.transpileModule(source, {
    compilerOptions: {
      module: ts.ModuleKind.ESNext,
      target: ts.ScriptTarget.ES2022,
    },
    fileName: `${locale}.ts`,
  }).outputText
  const url = `data:text/javascript;base64,${Buffer.from(javascript).toString('base64')}`
  return (await import(url)).default
}

function flatten(value, prefix = '', output = new Map()) {
  for (const [key, nested] of Object.entries(value ?? {})) {
    const path = prefix ? `${prefix}.${key}` : key
    if (nested && typeof nested === 'object' && !Array.isArray(nested)) {
      flatten(nested, path, output)
    } else {
      output.set(path, nested)
    }
  }
  return output
}

function placeholders(value) {
  return [...String(value).matchAll(/\{([A-Za-z0-9_]+)\}/g)]
    .map((match) => match[1])
    .sort()
    .join(',')
}

const catalogs = Object.fromEntries(
  await Promise.all(locales.map(async (locale) => [locale, await loadCatalog(locale)])),
)

for (const [domain, keys] of Object.entries(domainKeys)) {
  const domainCatalogs = Object.fromEntries(locales.map((locale) => [
    locale,
    Object.fromEntries(keys.filter((key) => key in catalogs[locale]).map((key) => (
      [key, catalogs[locale][key]]
    ))),
  ]))
  const english = flatten(domainCatalogs.en)
  const chinese = flatten(domainCatalogs['zh-CN'])
  const missingEnglish = [...chinese.keys()].filter((key) => !english.has(key))
  const missingChinese = [...english.keys()].filter((key) => !chinese.has(key))
  const placeholderMismatches = [...english.keys()].filter((key) => (
    chinese.has(key) && placeholders(english.get(key)) !== placeholders(chinese.get(key))
  ))
  if (missingEnglish.length || missingChinese.length || placeholderMismatches.length) {
    throw new Error(
      `${domain} locale parity failed: missing en=${missingEnglish.join(',')} `
        + `missing zh-CN=${missingChinese.join(',')} placeholders=${placeholderMismatches.join(',')}`,
    )
  }

  for (const locale of locales) {
    const directory = resolve(outputRoot, locale)
    mkdirSync(directory, { recursive: true })
    writeFileSync(
      resolve(directory, `${domain}.ts`),
      `export default ${JSON.stringify(domainCatalogs[locale], null, 2)} as Record<string, unknown>\n`,
      'utf8',
    )
  }
}
