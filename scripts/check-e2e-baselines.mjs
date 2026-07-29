import { existsSync, readFileSync, readdirSync } from 'node:fs'
import { dirname, join, relative, resolve } from 'node:path'
import process from 'node:process'

const root = process.cwd()
const manifestPath = join(root, 'test/e2e/screenshot-manifest.json')
const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'))

if (manifest.version !== 1 || !Array.isArray(manifest.files)) {
  throw new Error('screenshot manifest must contain version=1 and a files array')
}

const duplicates = manifest.files.filter((entry, index) => manifest.files.indexOf(entry) !== index)
if (duplicates.length) throw new Error(`duplicate screenshot manifest entries: ${duplicates.join(', ')}`)

const missing = manifest.files.filter((entry) => !existsSync(join(root, entry)))
const screenshotRoot = resolve(root, 'test/e2e/__screenshots__')
const actual = existsSync(screenshotRoot)
  ? readdirSync(screenshotRoot, { recursive: true, encoding: 'utf8' })
      .filter((entry) => entry.endsWith('.png'))
      .map((entry) => relative(root, resolve(screenshotRoot, entry)).replaceAll('\\', '/'))
      .sort()
  : []
const unexpected = actual.filter((entry) => !manifest.files.includes(entry))

if (missing.length || unexpected.length) {
  if (missing.length) {
    process.stderr.write(`Missing approved E2E screenshot baselines:\n${missing.map((entry) => `  - ${entry}`).join('\n')}\n`)
  }
  if (unexpected.length) {
    process.stderr.write(`Unexpected E2E screenshot baselines:\n${unexpected.map((entry) => `  - ${entry}`).join('\n')}\n`)
  }
  process.stderr.write(
    'Generate intentionally with npm run test:e2e:update, review every image, then commit the approved PNG files.\n',
  )
  process.exitCode = 1
} else {
  process.stdout.write(`E2E screenshot baseline manifest passed (${actual.length} images).\n`)
}
