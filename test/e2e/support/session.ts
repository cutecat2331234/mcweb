import { expect, type Page } from '@playwright/test'

export const acceptanceOwner = {
  email: process.env.MCWEB_E2E_OWNER_EMAIL || 'e2e-owner@mcweb.test',
  password: process.env.MCWEB_E2E_OWNER_PASSWORD || 'E2e-password-123!',
}

export async function signInAsAcceptanceOwner(page: Page) {
  await page.goto('/app/identity/sign-in?locale=en')
  await page.getByRole('textbox', { name: 'Email', exact: true }).fill(acceptanceOwner.email)
  await page.getByRole('textbox', { name: 'Password', exact: true }).fill(acceptanceOwner.password)

  const responsePromise = page.waitForResponse(
    (response) =>
      response.request().method() === 'POST' &&
      new URL(response.url()).pathname === '/app/identity/session',
  )
  await page.getByRole('button', { name: 'Sign in', exact: true }).click()
  const response = await responsePromise
  expect(response.status(), 'acceptance owner sign-in response').toBeLessThan(400)
  await expect(page).not.toHaveURL(/\/identity\/sign-in/)
}
