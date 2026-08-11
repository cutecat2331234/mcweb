import { mkdir, rm, writeFile } from 'node:fs/promises'
import { dirname, resolve } from 'node:path'

import type { Browser, BrowserContext } from '@playwright/test'

type AcceptanceCredentials = {
  email: string
  password: string
}

export type AcceptanceIdentity = AcceptanceCredentials & {
  key: string
}

const identityKeyPattern = /^[a-z][a-z0-9_-]{0,31}$/
const authStateDirectory = resolve(process.cwd(), 'tmp', 'e2e-auth')
const sessionTokenCookiePattern = /(?:^|_)session_token$/
type BrowserStorageState = Awaited<ReturnType<BrowserContext['storageState']>>

export function acceptanceAuthStatePath(identityKey: string) {
  if (!identityKeyPattern.test(identityKey)) {
    throw new Error(`Invalid acceptance identity key: ${identityKey}`)
  }

  return resolve(authStateDirectory, `${identityKey}.json`)
}

export async function clearAcceptanceAuthStates() {
  await rm(authStateDirectory, { recursive: true, force: true })
}

export async function captureAcceptanceAuthStates(
  browser: Browser,
  baseURL: string,
  identities: AcceptanceIdentity[],
) {
  if (identities.length === 0) {
    throw new Error('At least one acceptance identity is required')
  }

  const identityKeys = new Set<string>()
  for (const identity of identities) {
    acceptanceAuthStatePath(identity.key)
    if (identityKeys.has(identity.key)) {
      throw new Error(`Duplicate acceptance identity key: ${identity.key}`)
    }
    identityKeys.add(identity.key)
  }

  await clearAcceptanceAuthStates()
  for (const { key, ...credentials } of identities) {
    await captureAcceptanceAuthState(browser, baseURL, key, credentials)
  }
}

export function isolateAcceptanceAuthState(
  capturedState: BrowserStorageState,
  identityKey: string,
) {
  const sessionCookies = capturedState.cookies.filter((cookie) =>
    sessionTokenCookiePattern.test(cookie.name),
  )
  if (sessionCookies.length !== 1) {
    throw new Error(
      `Expected one authentication cookie for ${identityKey}; found ${sessionCookies.length}`,
    )
  }
  if (!sessionCookies[0].httpOnly) {
    throw new Error(`Authentication cookie for ${identityKey} must be HTTP-only`)
  }

  return { cookies: sessionCookies, origins: [] }
}

async function captureAcceptanceAuthState(
  browser: Browser,
  baseURL: string,
  identityKey: string,
  credentials: AcceptanceCredentials,
) {
  const statePath = acceptanceAuthStatePath(identityKey)
  const context = await browser.newContext({
    baseURL,
    colorScheme: 'light',
    locale: 'en-US',
    timezoneId: 'Asia/Shanghai',
  })

  try {
    const page = await context.newPage()
    await page.goto('/app/identity/sign-in?locale=en')
    await page.getByRole('textbox', { name: 'Email', exact: true }).fill(credentials.email)
    await page.getByRole('textbox', { name: 'Password', exact: true }).fill(credentials.password)

    const responsePromise = page.waitForResponse(
      (response) =>
        response.request().method() === 'POST' &&
        new URL(response.url()).pathname === '/app/identity/session',
    )
    await page.getByRole('button', { name: 'Sign in', exact: true }).click()
    const response = await responsePromise
    if (response.status() >= 400) {
      throw new Error(`${identityKey} acceptance sign-in returned HTTP ${response.status()}`)
    }
    await page.waitForURL((url) => !url.pathname.endsWith('/identity/sign-in'))

    const capturedState = await context.storageState()
    const isolatedState = isolateAcceptanceAuthState(capturedState, identityKey)

    await mkdir(dirname(statePath), { recursive: true })
    await writeFile(
      statePath,
      `${JSON.stringify(isolatedState, null, 2)}\n`,
      { encoding: 'utf8', mode: 0o600 },
    )
  } finally {
    await context.close()
  }
}
