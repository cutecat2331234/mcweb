import { expect, test } from './support/fixtures'
import {
  expectKeyboardFocusIndicator,
  expectNoAccessibilityViolations,
  expectReducedMotion,
} from './support/accessibility'
import { acceptanceAuthStatePath } from './support/auth-state'

const screenshotMasks = [
  '[data-testid="volatile-timestamp"]',
  '.arco-spin-icon',
]

test.use({ storageState: acceptanceAuthStatePath('owner'), diagnosticApplication: 'admin' })

test('admin metrics filtering preserves the mounted document', async ({ page, browserDiagnostics }) => {
  browserDiagnostics.setStep('Open Admin background jobs')
  await page.goto('/admin/system/jobs?locale=en')
  await expect(page.getByTestId('admin-jobs-page')).toBeVisible()
  await page.evaluate(() => {
    Object.assign(window, { __mcwebAcceptanceMountMarker: crypto.randomUUID() })
  })
  const marker = await page.evaluate(
    () => (window as typeof window & { __mcwebAcceptanceMountMarker?: string })
      .__mcwebAcceptanceMountMarker,
  )

  browserDiagnostics.setStep('Filter Admin metrics to seven days')
  const [metricsResponse] = await Promise.all([
    page.waitForResponse((response) => {
      const url = new URL(response.url())
      return (
        response.request().method() === 'GET' &&
        url.pathname === '/admin/system/jobs' &&
        url.searchParams.get('range') === '7d'
      )
    }),
    page.getByTestId('metrics-range').getByText('7 days', { exact: true }).click(),
  ])
  expect(metricsResponse.status()).toBeLessThan(400)
  await expect(page.getByTestId('metrics-range').locator('input[value="7d"]')).toBeChecked()
  expect(
    await page.evaluate(
      () => (window as typeof window & { __mcwebAcceptanceMountMarker?: string })
        .__mcwebAcceptanceMountMarker,
    ),
    'an Inertia filter must not replace the browser document',
  ).toBe(marker)
})

test('admin navigation preserves the mounted shell and sidebar state', async ({ page, browserDiagnostics }, testInfo) => {
  test.skip(testInfo.project.name === 'mobile-chromium', 'desktop sidebar state contract')

  browserDiagnostics.setStep('Open Admin jobs and collapse the sidebar')
  await page.goto('/admin/system/jobs?locale=en')
  const shell = page.locator('.arco-admin-layout')
  const sider = page.locator('.arco-admin-sider')
  const marker = crypto.randomUUID()

  await expect(shell).toBeVisible()
  await shell.evaluate((element, value) => {
    ;(element as HTMLElement).dataset.acceptanceShellMarker = value
  }, marker)
  await page.locator('.arco-admin-collapse-trigger').click()
  await expect(sider).toHaveClass(/arco-layout-sider-collapsed/)

  browserDiagnostics.setStep('Navigate from jobs to the Admin dashboard')
  await page.locator('.arco-admin-brand__link').click()
  await expect(page).toHaveURL(/\/admin(?:\?.*)?$/)
  await expect(sider).toHaveClass(/arco-layout-sider-collapsed/)
  await expect(shell).toHaveAttribute('data-acceptance-shell-marker', marker)
})

test('key admin page is bilingual on desktop and mobile', async ({ page, browserDiagnostics }) => {
  browserDiagnostics.setStep('Render Admin jobs in English')
  await page.goto('/admin/system/jobs?locale=en')
  await expect(
    page.getByTestId('admin-jobs-header').locator('.arco-page-header-title'),
  ).toHaveText('Background jobs')
  await expect(page).toHaveScreenshot('jobs-en.png', {
    mask: screenshotMasks.map((selector) => page.locator(selector)),
  })

  browserDiagnostics.setStep('Render Admin jobs in Chinese')
  await page.goto('/admin/system/jobs?locale=zh-CN')
  await expect(
    page.getByTestId('admin-jobs-header').locator('.arco-page-header-title'),
  ).toHaveText('后台任务')
  await expect(page).toHaveScreenshot('jobs-zh-CN.png', {
    mask: screenshotMasks.map((selector) => page.locator(selector)),
  })
})

test('empty and long-copy layouts remain usable', async ({ page }) => {
  await page.goto('/admin/system/jobs?locale=en')
  await expect(page.getByTestId('metrics-empty-state')).toBeVisible()

  await page.getByTestId('admin-jobs-header').locator('.arco-page-header-title').evaluate((element) => {
    element.textContent =
      'A deliberately long translated administration heading that verifies wrapping without hiding actions or introducing document-level horizontal scrolling'
  })

  const overflow = await page.evaluate(
    () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
  )
  expect(overflow, 'long translated copy must not overflow the document').toBeLessThanOrEqual(1)
  await expect(page).toHaveScreenshot('jobs-empty-long.png', {
    mask: screenshotMasks.map((selector) => page.locator(selector)),
  })
})

test('keyboard focus indicator is reachable through real Tab navigation', async ({ page }) => {
  await page.goto('/admin/system/jobs?locale=en')
  await expect(page.getByTestId('admin-jobs-page')).toBeVisible()
  await expectKeyboardFocusIndicator(page)
})

test('ARIA, contrast, and reduced motion gates pass', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' })
  await page.goto('/admin/system/jobs?locale=en')
  await expectNoAccessibilityViolations(page)
  await expectReducedMotion(page)
})
