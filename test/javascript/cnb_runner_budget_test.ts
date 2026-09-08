import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

const config = readFileSync(resolve(process.cwd(), '.cnb.yml'), 'utf8')
const pushPipelines = config.split(/^  web_trigger_/m, 1)[0]

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
