import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import test from 'node:test'

const projectRoot = fileURLToPath(new URL('../../', import.meta.url))
const resolver = `
  import { resolveConfig } from 'vite'
  const config = await resolveConfig(
    { configFile: 'vite.config.ts' },
    'build',
    'production',
  )
  process.stdout.write(JSON.stringify({
    minify: config.build.minify,
    sourcemap: config.build.sourcemap,
  }))
`

function resolveBuild(overrides: Record<string, string | undefined>) {
  const environment = { ...process.env }
  for (const key of [
    'MCWEB_DEVELOPER_VITE',
    'MCWEB_DEVELOPER_VITE_MINIFICATION',
    'MCWEB_DEVELOPER_VITE_SOURCE_MAPS',
  ]) {
    delete environment[key]
  }
  for (const [key, value] of Object.entries(overrides)) {
    if (value === undefined) delete environment[key]
    else environment[key] = value
  }

  const result = spawnSync(
    process.execPath,
    ['--input-type=module', '--eval', resolver],
    {
      cwd: projectRoot,
      encoding: 'utf8',
      env: environment,
    },
  )
  assert.equal(result.status, 0, `${result.stderr}\n${result.stdout}`)
  return JSON.parse(result.stdout)
}

test('Vite keeps public source maps disabled outside Developer Mode', () => {
  const baseline = resolveBuild({})
  const ignoredOverrides = resolveBuild({
    MCWEB_DEVELOPER_VITE_MINIFICATION: 'disabled',
    MCWEB_DEVELOPER_VITE_SOURCE_MAPS: 'disabled',
  })

  assert.equal(baseline.sourcemap, false)
  assert.deepEqual(ignoredOverrides, baseline)
})

test('Vite applies both Developer Mode build enum branches', () => {
  const baseline = resolveBuild({})

  assert.deepEqual(
    resolveBuild({
      MCWEB_DEVELOPER_VITE: '1',
      MCWEB_DEVELOPER_VITE_MINIFICATION: 'disabled',
      MCWEB_DEVELOPER_VITE_SOURCE_MAPS: 'enabled',
    }),
    { minify: false, sourcemap: true },
  )
  assert.deepEqual(
    resolveBuild({
      MCWEB_DEVELOPER_VITE: '1',
      MCWEB_DEVELOPER_VITE_MINIFICATION: 'enabled',
      MCWEB_DEVELOPER_VITE_SOURCE_MAPS: 'disabled',
    }),
    { minify: baseline.minify, sourcemap: false },
  )
})
