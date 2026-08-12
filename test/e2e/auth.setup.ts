import { test as setup } from '@playwright/test'

import { captureAcceptanceAuthStates } from './support/auth-state'
import { acceptanceOwner } from './support/session'

// The first Rails request on a clean Windows acceptance run can spend most of
// the default test budget loading application code. Keep regular scenarios at
// Playwright's default while giving the one-time authentication setup enough
// room to finish its real UI sign-in.
setup.setTimeout(120_000)

setup('capture acceptance owner session', async ({ browser, baseURL }) => {
  if (!baseURL) throw new Error('Playwright baseURL is required for acceptance authentication')

  await captureAcceptanceAuthStates(browser, baseURL, [
    { key: 'owner', ...acceptanceOwner },
  ])
})
