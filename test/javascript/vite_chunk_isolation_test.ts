import assert from 'node:assert/strict'
import { readFileSync, readdirSync } from 'node:fs'
import { posix, resolve } from 'node:path'
import test from 'node:test'

function sharedArcoGroups() {
  const source = readFileSync(resolve(process.cwd(), 'vite.config.ts'), 'utf8')
  const plan = source.slice(source.indexOf('const arcoChunkPlan'), source.indexOf('function chunkTokens'))
  return [...plan.matchAll(/\{\s*name:\s*'([^']+)'([\s\S]*?)\n  \}/g)].map((match) => {
    const tokens = (key: string) => (
      match[2].match(new RegExp(`${key}:\\s*'([^']*)'`))?.[1].split(/\s+/).filter(Boolean) ?? []
    )
    return {
      name: match[1],
      areas: tokens('areas'),
      icons: tokens('icons'),
      paths: tokens('paths'),
      packages: tokens('packages'),
    }
  })
}

test('shared Arco internals remain isolated to the application entries that use them', () => {
  const source = readFileSync(resolve(process.cwd(), 'vite.config.ts'), 'utf8')
  const generatedGroups = source.slice(source.indexOf('...arcoChunkGroups.map'))

  assert.match(generatedGroups, /includeDependenciesRecursively:\s*false/)
  assert.match(generatedGroups, /entriesAware:\s*true/)
  assert.match(generatedGroups, /entriesAwareMergeThreshold:\s*0/)
})

test('shared Arco chunks only depend on their own or lower-level runtime groups', () => {
  const runtimeRoot = resolve(process.cwd(), 'node_modules/@arco-design/web-vue/es')
  const groups = sharedArcoGroups()
  assert.ok(groups.length > 0, 'The static Arco chunk plan must remain inspectable')

  const ownerOf = (runtimePath: string) => groups.findIndex((group) => (
    group.paths.includes(runtimePath)
      || group.areas.some((area) => runtimePath.startsWith(`${area}/`))
  ))

  for (const [groupIndex, group] of groups.entries()) {
    assert.deepEqual(group.icons, [], 'Public icons must remain owned by their actual importers')
    const paths = new Set([
      ...group.paths,
      ...group.areas.flatMap((area) => readdirSync(resolve(runtimeRoot, area), { recursive: true })
        .filter((file) => file.endsWith('.js'))
        .map((file) => `${area}/${file.replaceAll('\\', '/')}`)),
    ])

    for (const runtimePath of paths) {
      const source = readFileSync(resolve(runtimeRoot, runtimePath), 'utf8')
      const imports = source.matchAll(/^(?:import\s+(?:[^'"\r\n]*?\s+from\s+)?|export\s+[^'"\r\n]*?\s+from\s+)['"]([^'"]+)['"]/gm)
      for (const [, specifier] of imports) {
        if (specifier === 'vue' || /\.(?:css|less)$/.test(specifier)) continue
        const dependencyIndex = specifier.startsWith('.')
          ? ownerOf(posix.normalize(posix.join(posix.dirname(runtimePath), specifier)))
          : groups.findIndex((candidate) => candidate.packages.includes(specifier))
        assert.notEqual(
          dependencyIndex,
          -1,
          `${group.name}: ${runtimePath} imports ungrouped ${specifier}; shared internals must not pull public controls or icons into startup`,
        )
        assert.ok(
          dependencyIndex <= groupIndex,
          `${group.name}: ${runtimePath} imports a higher-level runtime group through ${specifier}`,
        )
      }
    }
  }
})

test('Arco locale state stays below public component chunks', () => {
  const provider = sharedArcoGroups().find((group) => group.name === 'arco-provider-runtime')
  assert.ok(provider)
  assert.ok(provider.paths.includes('locale/index.js'))
  assert.ok(provider.paths.includes('locale/lang/zh-cn.js'))
})
