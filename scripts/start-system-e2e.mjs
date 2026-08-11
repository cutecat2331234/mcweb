import { spawn } from 'node:child_process'
import { existsSync } from 'node:fs'
import { resolve } from 'node:path'
import process from 'node:process'

import { resolveSpawnInvocation } from './npm-cli-invocation.mjs'

const DEFAULT_TEST_SUFFIX = '_e2e'
const port = Number.parseInt(process.env.MCWEB_E2E_PORT || '3102', 10)

if (!Number.isInteger(port) || port < 1024 || port > 65535) {
  throw new Error('MCWEB_E2E_PORT must be an unprivileged TCP port')
}

const environment = {
  ...process.env,
  RAILS_ENV: 'test',
  TEST_ENV_NUMBER: DEFAULT_TEST_SUFFIX,
  PARALLEL_WORKERS: '1',
  MCWEB_DEVELOPER_MODE: '0',
  LOCKBOX_MASTER_KEY:
    process.env.LOCKBOX_MASTER_KEY ||
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
}

if (process.env.MCWEB_E2E_DATABASE_URL) {
  const databaseUrl = new URL(process.env.MCWEB_E2E_DATABASE_URL)
  const databaseName = decodeURIComponent(databaseUrl.pathname.split('/').pop() || '')
  if (!databaseName.endsWith(DEFAULT_TEST_SUFFIX)) {
    throw new Error(
      `MCWEB_E2E_DATABASE_URL database must end with ${DEFAULT_TEST_SUFFIX}; received ${databaseName}`,
    )
  }
  environment.DATABASE_URL = databaseUrl.toString()
  const isolatedLocalConfig = resolve(
    process.cwd(),
    'tmp',
    `system-e2e-no-local-config-${process.pid}.yml`,
  )
  if (existsSync(isolatedLocalConfig)) {
    throw new Error(`Refusing existing E2E local config override: ${isolatedLocalConfig}`)
  }
  environment.MCWEB_LOCAL_CONFIG_PATH = isolatedLocalConfig
} else {
  delete environment.DATABASE_URL
}

function runStep(label, executable, args) {
  process.stdout.write(`[system-e2e] ${label}\n`)
  return new Promise((resolvePromise, rejectPromise) => {
    const invocation = resolveSpawnInvocation(executable, args)
    const child = spawn(invocation.executable, invocation.args, {
      cwd: process.cwd(),
      env: environment,
      stdio: 'inherit',
      windowsHide: true,
    })
    child.once('error', rejectPromise)
    child.once('exit', (code, signal) => {
      if (code === 0) resolvePromise()
      else rejectPromise(new Error(`${label} failed (${signal || `exit ${code}`})`))
    })
  })
}

if (process.env.MCWEB_E2E_SKIP_BUILD !== '1') {
  await runStep('build Tailwind test assets', 'ruby', ['bin/rails', 'tailwindcss:build'])
  await runStep('build Vite test assets', 'ruby', ['bin/vite', 'build', '--mode=test'])
}
await runStep('prepare isolated database', 'ruby', ['bin/rails', 'db:prepare'])
await runStep('seed deterministic acceptance owner', 'ruby', [
  'bin/rails',
  'runner',
  'test/e2e/support/seed.rb',
])

process.stdout.write(`[system-e2e] serving ${port}\n`)
const server = spawn(
  'ruby',
  ['bin/rails', 'server', '--binding', '127.0.0.1', '--port', String(port)],
  {
    cwd: process.cwd(),
    env: environment,
    stdio: 'inherit',
    windowsHide: true,
  },
)

let stopping = false
function stop(signal) {
  if (stopping) return
  stopping = true
  server.kill(signal)
}

process.once('SIGINT', () => stop('SIGINT'))
process.once('SIGTERM', () => stop('SIGTERM'))
server.once('error', (error) => {
  process.stderr.write(`[system-e2e] server failed: ${error.message}\n`)
  process.exitCode = 1
})
server.once('exit', (code, signal) => {
  if (!stopping && code !== 0) {
    process.stderr.write(`[system-e2e] server exited (${signal || `exit ${code}`})\n`)
    process.exitCode = code || 1
  }
})
