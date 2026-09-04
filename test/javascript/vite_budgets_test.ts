import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import {
  mkdirSync,
  mkdtempSync,
  rmSync,
  writeFileSync,
} from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import test from 'node:test'

const checkerPath = fileURLToPath(new URL('../../scripts/check-vite-budgets.mjs', import.meta.url))

function writeFixtureFile(root: string, path: string, contents: string) {
  const absolutePath = join(root, ...path.split('/'))
  mkdirSync(dirname(absolutePath), { recursive: true })
  writeFileSync(absolutePath, contents, 'utf8')
}

function writeFixtureJson(root: string, path: string, value: unknown) {
  writeFixtureFile(root, path, `${JSON.stringify(value, null, 2)}\n`)
}

function withFixture(run: (root: string) => void) {
  const root = mkdtempSync(join(tmpdir(), 'mcweb-vite-budget-'))
  try {
    run(root)
  } finally {
    rmSync(root, { recursive: true, force: true })
  }
}

function runChecker(root: string) {
  return spawnSync(process.execPath, [checkerPath], {
    cwd: root,
    encoding: 'utf8',
  })
}

function writeBaseForum(root: string, maxInitialJavaScriptBytes: number) {
  writeFixtureJson(root, 'config/frontend_applications/base/forum.json', {
    id: 'forum',
    runtime_kind: 'inertia',
    entrypoint: 'forum',
    budget: {
      representative_paths: ['/app/forum/latest'],
      representative_components: ['Community/Latest/Index'],
      max_initial_javascript_bytes: maxInitialJavaScriptBytes,
    },
  })
  writeFixtureFile(root, 'public/vite/assets/forum.js', 'f'.repeat(96))
  writeFixtureFile(root, 'public/vite/assets/latest.js', 'p'.repeat(96))
}

test('Vite initial budgets exclude lazy imports while retaining static imports', () => {
  withFixture((root) => {
    writeBaseForum(root, 512)
    writeFixtureJson(root, 'public/vite/.vite/manifest.json', {
      'entrypoints/forum.ts': {
        file: 'assets/forum.js',
        imports: ['_shared.js'],
        dynamicImports: ['pages/Unused/Large.vue'],
        assets: ['assets/large-image.webp'],
      },
      'pages/Community/Latest/Index.vue': {
        file: 'assets/latest.js',
        imports: ['_shared.js'],
        dynamicImports: ['pages/Unused/Drawer.vue'],
      },
      '_shared.js': { file: 'assets/shared.js' },
      'pages/Unused/Large.vue': { file: 'assets/large.js' },
      'pages/Unused/Drawer.vue': { file: 'assets/drawer.js' },
    })
    writeFixtureFile(root, 'public/vite/assets/shared.js', 's'.repeat(96))
    writeFixtureFile(root, 'public/vite/assets/large.js', 'l'.repeat(4096))
    writeFixtureFile(root, 'public/vite/assets/drawer.js', 'd'.repeat(4096))
    writeFixtureFile(root, 'public/vite/assets/large-image.webp', 'i'.repeat(4096))

    const result = runChecker(root)

    assert.equal(result.status, 0, `${result.stderr}\n${result.stdout}`)
    assert.match(result.stdout, /Community\/Latest\/Index/)
  })
})

test('Vite budgets resolve contributed page roots outside the base source tree', () => {
  withFixture((root) => {
    writeBaseForum(root, 1024)
    writeFixtureJson(root, 'config/frontend_applications/contributions/ee_channel.json', {
      contribution_id: 'ee.channel.application',
      product_owner: 'ee',
      runtime_owner: 'ee',
      adapter_module: 'app/javascript/frontend-application-adapters/channel/ee-channel.ts',
      page_roots: ['ee/app/javascript/pages'],
      creates_application: {
        id: 'channel',
        entrypoint: 'channel',
        budget: {
          representative_paths: ['/app/chat'],
          representative_components: ['Ee/EnterpriseShell'],
          max_initial_javascript_bytes: 1024,
        },
      },
    })
    writeFixtureJson(root, 'public/vite/.vite/manifest.json', {
      'entrypoints/forum.ts': { file: 'assets/forum.js' },
      'pages/Community/Latest/Index.vue': { file: 'assets/latest.js' },
      'entrypoints/channel.ts': {
        file: 'assets/channel.js',
        dynamicImports: ['../../ee/app/javascript/pages/Ee/EnterpriseShell.vue'],
      },
      '../../ee/app/javascript/pages/Ee/EnterpriseShell.vue': {
        file: 'assets/enterprise-shell.js',
        src: '../../ee/app/javascript/pages/Ee/EnterpriseShell.vue',
      },
    })
    writeFixtureFile(root, 'public/vite/assets/channel.js', 'c'.repeat(96))
    writeFixtureFile(root, 'public/vite/assets/enterprise-shell.js', 'e'.repeat(96))

    const result = runChecker(root)

    assert.equal(result.status, 0, `${result.stderr}\n${result.stdout}`)
    assert.match(result.stdout, /Ee\/EnterpriseShell/)
  })
})

test('inlined adapter budgets include the representative route page', () => {
  withFixture((root) => {
    writeBaseForum(root, 1024)
    const contribution = {
      contribution_id: 'ee.forum.realtime',
      product_owner: 'ee',
      runtime_owner: 'ce',
      extends_application: 'forum',
      adapter_module: 'app/javascript/frontend-application-adapters/forum/ee-realtime.ts',
      budget: {
        representative_paths: ['/app/forum/latest'],
        representative_entries: [
          'app/javascript/frontend-application-adapters/forum/ee-realtime.ts',
        ],
        max_initial_javascript_bytes: 256,
      },
    }
    writeFixtureJson(
      root,
      'config/frontend_applications/contributions/ee_forum_realtime.json',
      contribution,
    )
    writeFixtureJson(root, 'public/vite/.vite/manifest.json', {
      'entrypoints/forum.ts': {
        file: 'assets/forum.js',
        imports: ['_ee-realtime.js'],
      },
      'pages/Community/Latest/Index.vue': { file: 'assets/latest.js' },
      '_ee-realtime.js': { file: 'assets/ee-realtime.js' },
    })
    writeFixtureFile(root, 'public/vite/assets/ee-realtime.js', 'r'.repeat(32))
    writeFixtureFile(
      root,
      'app/javascript/frontend-application-adapters/forum/ee-realtime.ts',
      'export default {}\n',
    )

    const passingResult = runChecker(root)

    assert.equal(passingResult.status, 0, `${passingResult.stderr}\n${passingResult.stdout}`)
    assert.match(passingResult.stdout, /ee-realtime\.ts/)

    contribution.budget.max_initial_javascript_bytes = 208
    writeFixtureJson(
      root,
      'config/frontend_applications/contributions/ee_forum_realtime.json',
      contribution,
    )
    const staticDependencyFailure = runChecker(root)

    assert.equal(
      staticDependencyFailure.status,
      1,
      `${staticDependencyFailure.stderr}\n${staticDependencyFailure.stdout}`,
    )
    assert.match(
      staticDependencyFailure.stderr,
      /Frontend application performance budget exceeded/,
    )

    contribution.budget.max_initial_javascript_bytes = 160
    writeFixtureJson(
      root,
      'config/frontend_applications/contributions/ee_forum_realtime.json',
      contribution,
    )
    writeFixtureJson(root, 'public/vite/.vite/manifest.json', {
      'entrypoints/forum.ts': { file: 'assets/forum.js' },
      'pages/Community/Latest/Index.vue': { file: 'assets/latest.js' },
    })
    const routePageFailure = runChecker(root)

    assert.equal(
      routePageFailure.status,
      1,
      `${routePageFailure.stderr}\n${routePageFailure.stdout}`,
    )
    assert.match(routePageFailure.stderr, /Frontend application performance budget exceeded/)

    rmSync(
      join(
        root,
        'app',
        'javascript',
        'frontend-application-adapters',
        'forum',
        'ee-realtime.ts',
      ),
    )
    const missingSourceFailure = runChecker(root)

    assert.equal(
      missingSourceFailure.status,
      1,
      `${missingSourceFailure.stderr}\n${missingSourceFailure.stdout}`,
    )
    assert.match(missingSourceFailure.stderr, /representative entry source is missing/)
  })
})

test('Vite initial budgets continue to fail for oversized static dependencies', () => {
  withFixture((root) => {
    writeBaseForum(root, 512)
    writeFixtureJson(root, 'public/vite/.vite/manifest.json', {
      'entrypoints/forum.ts': {
        file: 'assets/forum.js',
        imports: ['_large-static.js'],
      },
      'pages/Community/Latest/Index.vue': { file: 'assets/latest.js' },
      '_large-static.js': { file: 'assets/large-static.js' },
    })
    writeFixtureFile(root, 'public/vite/assets/large-static.js', 'x'.repeat(4096))

    const result = runChecker(root)

    assert.equal(result.status, 1, `${result.stderr}\n${result.stdout}`)
    assert.match(result.stderr, /Frontend application performance budget exceeded/)
  })
})
