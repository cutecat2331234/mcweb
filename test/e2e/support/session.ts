import { expect, type Page } from '@playwright/test'

export const acceptanceOwner = {
  email: process.env.MCWEB_E2E_OWNER_EMAIL || 'e2e-owner@mcweb.test',
  password: process.env.MCWEB_E2E_OWNER_PASSWORD || 'E2e-password-123!',
}

export async function signInAsAcceptanceOwner(page: Page) {
  await page.goto('/app/identity/sign-in?locale=en')
  await page.locator('#email').fill(acceptanceOwner.email)
  await page.locator('#password').fill(acceptanceOwner.password)

  const responsePromise = page.waitForResponse(
    (response) =>
      response.request().method() === 'POST' &&
      new URL(response.url()).pathname === '/app/identity/session',
  )
  await page.locator('form button[type="submit"]').click()
  const response = await responsePromise
  expect(response.status(), 'acceptance owner sign-in response').toBeLessThan(400)
  await expect(page).not.toHaveURL(/\/identity\/sign-in/)
}
