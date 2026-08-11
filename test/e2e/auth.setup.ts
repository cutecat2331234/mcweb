import { test as setup } from '@playwright/test'

import { captureAcceptanceAuthStates } from './support/auth-state'
import { acceptanceOwner } from './support/session'

setup('capture acceptance owner session', async ({ browser, baseURL }) => {
  if (!baseURL) throw new Error('Playwright baseURL is required for acceptance authentication')

  await captureAcceptanceAuthStates(browser, baseURL, [
    { key: 'owner', ...acceptanceOwner },
  ])
})
