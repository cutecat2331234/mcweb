import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

const config = readFileSync(resolve(process.cwd(), '.cnb.yml'), 'utf8')
const pushPipelines = config.split(/^  web_trigger_/m, 1)[0]
const packageJson = JSON.parse(
  readFileSync(resolve(process.cwd(), 'package.json'), 'utf8'),
) as { scripts?: Record<string, string> }

test('CNB push gates keep explicit right-sized runner allocations', () => {
  const allocations = [...pushPipelines.matchAll(
    /^    - name: ([^\r\n]+)\r?\n      runner:\r?\n        cpus: (\d+)$/gm,
  )].map((match) => ({ name: match[1], cpus: Number(match[2]) }))

  assert.equal(allocations.length, 8, 'every push pipeline must declare its runner size')
  assert.ok(allocations.every(({ cpus }) => cpus >= 1 && cpus <= 4))
  assert.ok(
    allocations.reduce((sum, { cpus }) => sum + cpus, 0) <= 27,
    'push pipelines must stay within the pre-freeze CPU budget',
  )
})

test('CNB dependency and service image caches remain synchronized', () => {
  const cacheBlocks = [...config.matchAll(
    /type: docker:cache\r?\n([\s\S]*?)(?=^        - name:|^      failStages:|^    - name:|(?![\s\S]))/gm,
  )].map((match) => match[1])

  assert.ok(cacheBlocks.length >= 6)
  for (const block of cacheBlocks) assert.match(block, /^            sync: true$/m)
})

test('every npm command referenced by CNB exists in package scripts', () => {
  const referencedScripts = [...config.matchAll(/\bnpm run (?:--if-present\s+)?([\w:-]+)/g)]
    .map((match) => match[1])

  assert.ok(referencedScripts.length > 0)
  assert.ok(referencedScripts.every((script) => !script.startsWith('--')))
  for (const script of referencedScripts) {
    assert.equal(
      typeof packageJson.scripts?.[script],
      'string',
      `.cnb.yml references an undefined package script: ${script}`,
    )
  }
})
