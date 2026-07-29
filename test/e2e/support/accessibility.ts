import { readFileSync } from 'node:fs'
import AxeBuilder from '@axe-core/playwright'
import { expect, type Page } from '@playwright/test'

type AccessibilityException = {
  path: string
  rule: string
  selector: string
  reason: string
}

type AccessibilityAllowlist = {
  version: number
  entries: AccessibilityException[]
}

const allowlist = JSON.parse(
  readFileSync(new URL('../accessibility-allowlist.json', import.meta.url), 'utf8'),
) as AccessibilityAllowlist

if (
  allowlist.version !== 1 ||
  !Array.isArray(allowlist.entries) ||
  allowlist.entries.some(
    (entry) =>
      !entry.path ||
      !entry.rule ||
      !entry.selector ||
      !entry.reason ||
      entry.reason.trim().length < 8,
  )
) {
  throw new Error('accessibility allowlist entries require path, rule, selector, and a concrete reason')
}

export async function expectNoAccessibilityViolations(page: Page) {
  const pathname = new URL(page.url()).pathname
  const results = await new AxeBuilder({ page })
    .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'])
    .analyze()

  const violations = results.violations.flatMap((violation) =>
    violation.nodes.map((node) => ({
      rule: violation.id,
      selector: node.target.map(String).join(' '),
      impact: node.impact,
      help: violation.help,
    })),
  )
  const unapproved = violations.filter(
    (violation) =>
      !allowlist.entries.some(
        (entry) =>
          entry.path === pathname &&
          entry.rule === violation.rule &&
          entry.selector === violation.selector,
      ),
  )

  expect(
    unapproved,
    unapproved
      .map(
        (violation) =>
          `${violation.rule} (${violation.impact}) ${violation.selector}: ${violation.help}`,
      )
      .join('\n'),
  ).toEqual([])
}

export async function expectKeyboardFocusIndicator(page: Page) {
  let focused = page.locator(':focus')
  for (let attempt = 0; attempt < 8; attempt += 1) {
    await page.keyboard.press('Tab')
    focused = page.locator(':focus')
    if ((await focused.count()) > 0 && (await focused.first().isVisible())) break
  }

  await expect(focused.first()).toBeVisible()
  const hasIndicator = await focused.first().evaluate((element) => {
    const style = getComputedStyle(element)
    const outlineVisible =
      style.outlineStyle !== 'none' && Number.parseFloat(style.outlineWidth) > 0
    const shadowVisible = style.boxShadow !== 'none'
    return outlineVisible || shadowVisible
  })
  expect(hasIndicator, 'keyboard focus must have an outline or focus ring').toBe(true)
}

export async function expectReducedMotion(page: Page) {
  const offenders = await page.locator('.mcweb-admin *').evaluateAll((elements) => {
    function milliseconds(value: string) {
      return value.split(',').map((part) => {
        const token = part.trim()
        return token.endsWith('ms')
          ? Number.parseFloat(token)
          : Number.parseFloat(token) * 1000
      })
    }

    return elements.flatMap((element) => {
      const style = getComputedStyle(element)
      const durations = [
        ...milliseconds(style.animationDuration),
        ...milliseconds(style.transitionDuration),
      ].filter(Number.isFinite)
      return durations.some((duration) => duration > 1)
        ? [`${element.tagName.toLowerCase()}.${element.className}`]
        : []
    }).slice(0, 20)
  })

  expect(offenders, 'reduced-motion mode left animations longer than 1ms').toEqual([])
}
