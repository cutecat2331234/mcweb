import { test as teardown } from '@playwright/test'

import { clearAcceptanceAuthStates } from './support/auth-state'

teardown('remove acceptance session states', async () => {
  await clearAcceptanceAuthStates()
})
