import assert from 'node:assert/strict'
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import process from 'node:process'
import test from 'node:test'

import {
  resolveNpmCliInvocation,
  resolveSpawnInvocation,
} from '../../scripts/npm-cli-invocation.mjs'

const harnessSource = readFileSync('scripts/start-system-e2e.mjs', 'utf8')

function withFakeNpmCli(run: (npmCliPath: string) => void) {
  const directory = mkdtempSync(join(tmpdir(), 'mcweb-e2e-npm-'))
  const npmCliPath = join(directory, 'npm-cli.js')
  writeFileSync(npmCliPath, '// test fixture\n', 'utf8')
  try {
    run(npmCliPath)
  } finally {
    rmSync(directory, { recursive: true, force: true })
  }
}

test('npm commands use the active Node executable without a command shell', () => {
  withFakeNpmCli((npmCliPath) => {
    const invocation = resolveSpawnInvocation('npm.cmd', ['--version'], {
      environment: {
        npm_execpath: npmCliPath,
        npm_node_execpath: process.execPath,
      },
      currentNodePath: process.execPath,
      platform: process.platform,
    })

    assert.equal(invocation.executable, process.execPath)
    assert.deepEqual(invocation.args, [npmCliPath, '--version'])
    assert.equal('shell' in invocation, false)
  })
})

test('npm command resolution fails closed for missing or unexpected CLI paths', () => {
  assert.throws(
    () => resolveNpmCliInvocation([], { environment: {} }),
    /npm_execpath is required/,
  )

  const environment = {
    npm_execpath: process.execPath,
    npm_node_execpath: process.execPath,
  }
  assert.throws(
    () => resolveNpmCliInvocation([], { environment }),
    /npm_execpath must reference npm-cli\.js/,
  )
})

test('npm command resolution rejects a different declared Node executable', () => {
  withFakeNpmCli((npmCliPath) => {
    assert.throws(
      () =>
        resolveNpmCliInvocation([], {
          environment: {
            npm_execpath: npmCliPath,
            npm_node_execpath: npmCliPath,
          },
          currentNodePath: process.execPath,
          platform: process.platform,
        }),
      /npm_node_execpath must identify the active Node\.js executable/,
    )
  })
})

test('non-npm commands remain unchanged', () => {
  assert.deepEqual(resolveSpawnInvocation('ruby', ['bin/rails']), {
    executable: 'ruby',
    args: ['bin/rails'],
  })
})

test('the system E2E harness normalizes commands without enabling a shell', () => {
  assert.match(harnessSource, /resolveSpawnInvocation\(executable, args\)/)
  assert.match(
    harnessSource,
    /spawn\(invocation\.executable, invocation\.args, \{/,
  )
  assert.doesNotMatch(harnessSource, /shell:\s*true/)
})
