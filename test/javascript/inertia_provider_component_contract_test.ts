import assert from 'node:assert/strict'
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

const entrypointRoots = [
  'app/javascript/entrypoints',
  'ee/app/javascript/entrypoints',
  'pvp/app/javascript/entrypoints',
]

function entrypointFiles(root: string): string[] {
  const absoluteRoot = resolve(process.cwd(), root)
  if (!existsSync(absoluteRoot)) return []

  return readdirSync(absoluteRoot).flatMap((name) => {
    const path = resolve(absoluteRoot, name)
    return statSync(path).isFile() && /\.[cm]?[jt]sx?$/.test(name) ? [path] : []
  })
}

test('Inertia entrypoints inject an actual provider component instead of a boolean sentinel', () => {
  for (const path of entrypointRoots.flatMap(entrypointFiles)) {
    const source = readFileSync(path, 'utf8')

    assert.doesNotMatch(source, /\bprovider\s*:/, `${path} uses the removed provider option`)
    assert.doesNotMatch(
      source,
      /providerComponent\s*:\s*true\b/,
      `${path} must pass a Vue component to providerComponent`,
    )
  }
})
