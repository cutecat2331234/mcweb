import { expect, test } from '@playwright/test'

import { expectNoAccessibilityViolations } from './support/accessibility'

test.describe('public sign-in interface', () => {
  test('keeps Chinese field rhythm and responsive actions geometrically stable', async ({ page }) => {
    const consoleErrors: string[] = []
    page.on('console', (message) => {
      if (message.type() === 'error') consoleErrors.push(message.text())
    })

    const response = await page.goto('/app/identity/sign-in?locale=zh-CN', {
      waitUntil: 'domcontentloaded',
    })
    expect(response?.ok()).toBe(true)
    await expect(page.locator('html')).toHaveAttribute('lang', 'zh-CN')

    const surface = page.getByTestId('auth-surface')
    const form = surface.locator('form')
    const fields = [
      { label: surface.locator('label[for="email"]'), input: form.locator('#email') },
      { label: surface.locator('label[for="password"]'), input: form.locator('#password') },
    ]

    await expect(surface).toBeVisible()
    await expect(form).toBeVisible()

    for (const field of fields) {
      const labelBox = await field.label.boundingBox()
      const inputBox = await field.input.boundingBox()
      expect(labelBox).not.toBeNull()
      expect(inputBox).not.toBeNull()
      expect(inputBox!.y - (labelBox!.y + labelBox!.height)).toBeGreaterThanOrEqual(7)
      expect(inputBox!.y - (labelBox!.y + labelBox!.height)).toBeLessThanOrEqual(9)
      expect(inputBox!.height).toBeGreaterThanOrEqual(44)
    }

    const submit = form.locator('button[type="submit"]')
    const submitBox = await submit.boundingBox()
    const formBox = await form.boundingBox()
    const surfaceBox = await surface.boundingBox()
    const viewport = page.viewportSize()
    expect(submitBox).not.toBeNull()
    expect(formBox).not.toBeNull()
    expect(surfaceBox).not.toBeNull()
    expect(viewport).not.toBeNull()
    expect(submitBox!.height).toBeGreaterThanOrEqual(44)

    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth)
    expect(overflow).toBeLessThanOrEqual(1)

    if (viewport!.width < 640) {
      expect(Math.abs(submitBox!.width - formBox!.width)).toBeLessThanOrEqual(1)
    } else {
      const surfaceCenter = surfaceBox!.x + (surfaceBox!.width / 2)
      expect(Math.abs(surfaceCenter - (viewport!.width / 2))).toBeLessThanOrEqual(1)
    }

    await expectNoAccessibilityViolations(page)
    expect(consoleErrors).toEqual([])
  })
})
