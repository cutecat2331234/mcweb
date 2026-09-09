import { acceptanceAuthStatePath } from './support/auth-state'
import { expect, test } from './support/fixtures'

// These are the authenticated representative routes in the CE account manifest.
// Sign-in is covered separately by auth-interface-quality and real auth setup.
const accountPages = ['/app/account', '/app/identity/security', '/app/minecraft/link']

test.use({ storageState: acceptanceAuthStatePath('owner'), diagnosticApplication: 'account' })

for (const locale of ['en', 'zh-CN']) {
  for (const path of accountPages) {
    test(`account application renders ${path} in ${locale}`, async ({ page, browserDiagnostics }) => {
      browserDiagnostics.setStep(`Open ${path} in ${locale}`)
      const response = await page.goto(`${path}?locale=${locale}`)
      expect(response?.status(), 'the authenticated CE account page must load').toBe(200)
      await expect(page).toHaveURL((url) => url.pathname === path)
      await expect(page.locator('html')).toHaveAttribute('data-mcweb-application', 'account')
      await expect(page.locator('html')).toHaveAttribute('lang', locale)
      await expect(page.locator('[data-mc-application-shell]')).toBeVisible()
      await expect(page.locator('#application-content .arco-page-header-title, #application-content h1').first()).toBeVisible()
      await expect(page.locator('.mc-application-error')).toHaveCount(0)
      browserDiagnostics.assertClean()
    })
  }
}
