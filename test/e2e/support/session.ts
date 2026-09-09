import { expect, type Page } from '@playwright/test'

import { submitAcceptanceSignIn } from './sign-in-navigation.ts'

export const acceptanceOwner = {
  email: process.env.MCWEB_E2E_OWNER_EMAIL || 'e2e-owner@mcweb.test',
  password: process.env.MCWEB_E2E_OWNER_PASSWORD || 'E2e-password-123!',
}

export async function signInAsAcceptanceOwner(page: Page) {
  await page.goto('/app/identity/sign-in?locale=en')
  await page.getByRole('textbox', { name: 'Email', exact: true }).fill(acceptanceOwner.email)
  await page.getByRole('textbox', { name: 'Password', exact: true }).fill(acceptanceOwner.password)

  await submitAcceptanceSignIn(page, 'owner')
  await expect(page).not.toHaveURL(/\/identity\/sign-in/)
  await page.locator('[data-mc-application-shell], .arco-admin-layout').first().waitFor({ state: 'visible' })
}
