import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { join, relative } from 'node:path'
import test from 'node:test'

import type { Browser } from '@playwright/test'

import {
  acceptanceAuthStatePath,
  captureAcceptanceAuthStates,
  isolateAcceptanceAuthState,
} from '../e2e/support/auth-state.ts'

const authSetupSource = readFileSync(
  new URL('../e2e/auth.setup.ts', import.meta.url),
  'utf8',
)

const cookie = (name: string, value = 'secret') => ({
  name,
  value,
  domain: '127.0.0.1',
  path: '/',
  expires: -1,
  httpOnly: true,
  secure: false,
  sameSite: 'Lax' as const,
})

test('acceptance auth state paths are ignored, per-identity temporary files', () => {
  assert.equal(
    relative(process.cwd(), acceptanceAuthStatePath('owner')),
    join('tmp', 'e2e-auth', 'owner.json'),
  )
  assert.notEqual(acceptanceAuthStatePath('owner'), acceptanceAuthStatePath('tester'))
  assert.throws(() => acceptanceAuthStatePath('../owner'), /Invalid acceptance identity key/)
})

test('acceptance auth state preserves only one dedicated authentication cookie', () => {
  const state = isolateAcceptanceAuthState(
    {
      cookies: [
        cookie('_mcweb_ee_session', 'rails-session'),
        cookie('MCWEB-EE-XSRF-TOKEN', 'csrf'),
        cookie('mcweb_ee_session_token', 'authentication'),
      ],
      origins: [
        {
          origin: 'http://127.0.0.1:3102',
          localStorage: [{ name: 'mc-theme', value: 'dark' }],
        },
      ],
    },
    'owner',
  )

  assert.deepEqual(state, {
    cookies: [cookie('mcweb_ee_session_token', 'authentication')],
    origins: [],
  })
})

test('acceptance auth state rejects missing or ambiguous authentication cookies', () => {
  assert.throws(
    () => isolateAcceptanceAuthState({ cookies: [], origins: [] }, 'owner'),
    /found 0/,
  )
  assert.throws(
    () =>
      isolateAcceptanceAuthState(
        {
          cookies: [cookie('session_token'), cookie('mcweb_ee_session_token')],
          origins: [],
        },
        'owner',
      ),
    /found 2/,
  )
  assert.throws(
    () =>
      isolateAcceptanceAuthState(
        {
          cookies: [{ ...cookie('session_token'), httpOnly: false }],
          origins: [],
        },
        'owner',
      ),
    /must be HTTP-only/,
  )
})

test('the managed E2E server never silently reuses a residual process', () => {
  const configSource = readFileSync(
    new URL('../../playwright.config.ts', import.meta.url),
    'utf8',
  )

  assert.match(configSource, /reuseExistingServer:\s*false/)
  assert.doesNotMatch(configSource, /reuseExistingServer:\s*!process\.env\.CI/)
  assert.match(configSource, /webServer:\s*externalServer\s*\?\s*undefined/)
})

test('one-time authentication setup allows a real cold Rails boot', () => {
  assert.match(authSetupSource, /setup\.setTimeout\(120_000\)/)
})

test('acceptance identity batches reject empty and duplicate identity sets', async () => {
  const unusedBrowser = {} as Browser
  const credentials = { email: 'ignored@example.test', password: 'ignored' }

  await assert.rejects(
    captureAcceptanceAuthStates(unusedBrowser, 'http://127.0.0.1:3102', []),
    /At least one acceptance identity/,
  )
  await assert.rejects(
    captureAcceptanceAuthStates(unusedBrowser, 'http://127.0.0.1:3102', [
      { key: 'owner', ...credentials },
      { key: 'owner', ...credentials },
    ]),
    /Duplicate acceptance identity key/,
  )
})
