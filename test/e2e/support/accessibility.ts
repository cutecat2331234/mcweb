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

const keyboardFocusableSelector = [
  'a[href]',
  'area[href]',
  'button:not([disabled])',
  'input:not([disabled]):not([type="hidden"])',
  'select:not([disabled])',
  'textarea:not([disabled])',
  'summary',
  '[contenteditable]:not([contenteditable="false"])',
  '[tabindex]:not([tabindex="-1"])',
].join(', ')

export async function expectKeyboardFocusIndicator(page: Page) {
  const tabStopBudget = await page.locator(keyboardFocusableSelector).evaluateAll((elements) =>
    elements.filter((element) => {
      if (!(element instanceof HTMLElement)) return false
      const style = getComputedStyle(element)
      return (
        element.tabIndex >= 0 &&
        !element.matches(':disabled') &&
        element.getAttribute('aria-disabled') !== 'true' &&
        !element.closest('[inert], [aria-hidden="true"]') &&
        element.getClientRects().length > 0 &&
        style.display !== 'none' &&
        style.visibility !== 'hidden' &&
        style.visibility !== 'collapse' &&
        Number.parseFloat(style.opacity) > 0
      )
    }).length,
  )
  expect(
    tabStopBudget,
    'the page must expose a visible, enabled control in the sequential keyboard order',
  ).toBeGreaterThan(0)

  await page.evaluate(() => {
    const previousTabIndex = document.body.getAttribute('tabindex')
    document.body.setAttribute('tabindex', '-1')
    document.body.focus({ preventScroll: true })
    if (previousTabIndex === null) document.body.removeAttribute('tabindex')
    else document.body.setAttribute('tabindex', previousTabIndex)
  })
  expect(
    await page.evaluate(() => document.activeElement === document.body),
    'the document body must provide a stable starting point before keyboard traversal',
  ).toBe(true)

  let indicator: Awaited<ReturnType<typeof readActiveFocusIndicator>> | null = null
  for (let attempt = 0; attempt < tabStopBudget; attempt += 1) {
    await page.keyboard.press('Tab')
    indicator = await readActiveFocusIndicator(page)
    if (indicator?.visibleInteractive) break
  }

  expect(
    indicator?.visibleInteractive,
    `Tab must reach a visible, enabled sequential control; checked ${tabStopBudget} tab stops and received ${JSON.stringify(indicator)}`,
  ).toBe(true)
  expect(indicator?.focusVisible, 'keyboard focus must match :focus-visible').toBe(true)
  expect(
    indicator?.outlineVisible || indicator?.shadowVisible,
    `keyboard focus must have a visible computed ring; received ${JSON.stringify(indicator)}`,
  ).toBe(true)
}

async function readActiveFocusIndicator(page: Page) {
  return page.evaluate(() => {
    const element = document.activeElement
    if (!(element instanceof HTMLElement) || element === document.body) return null

    const style = getComputedStyle(element)
    const rect = element.getBoundingClientRect()
    const transparent = (value: string) => {
      const normalized = value.trim().toLowerCase()
      return (
        normalized === 'transparent' ||
        /rgba\([^)]*,\s*0(?:\.0+)?\s*\)/.test(normalized) ||
        /rgb\([^)]*\/\s*0(?:\.0+)?%?\s*\)/.test(normalized)
      )
    }
    const visible =
      element.getClientRects().length > 0 &&
      style.display !== 'none' &&
      style.visibility !== 'hidden' &&
      style.visibility !== 'collapse' &&
      Number.parseFloat(style.opacity) > 0 &&
      rect.bottom > 0 &&
      rect.right > 0 &&
      rect.top < window.innerHeight &&
      rect.left < window.innerWidth
    const interactive =
      element.tabIndex >= 0 &&
      !element.matches(':disabled') &&
      element.getAttribute('aria-disabled') !== 'true' &&
      !element.closest('[inert], [aria-hidden="true"]')
    const outlineVisible =
      style.outlineStyle !== 'none' &&
      style.outlineStyle !== 'hidden' &&
      Number.parseFloat(style.outlineWidth) > 0 &&
      !transparent(style.outlineColor)
    const shadowVisible = style.boxShadow !== 'none' && !transparent(style.boxShadow)
    return {
      visibleInteractive: visible && interactive,
      focusVisible: element.matches(':focus-visible'),
      outlineVisible,
      shadowVisible,
      element: `${element.tagName.toLowerCase()}${element.id ? `#${element.id}` : ''}`,
      outline: `${style.outlineWidth} ${style.outlineStyle} ${style.outlineColor}`,
      boxShadow: style.boxShadow,
    }
  })
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
