// These intentional-failure probes use the base fixture: the assertions below
// must prove the shared guard rejects them, rather than failing their own test.
import { expect, test } from '@playwright/test'

import { captureBrowserDiagnostics } from './support/browser-diagnostics'

const probeOrigin = 'http://browser-diagnostics.mcweb.test'

test('diagnostic guard observes real browser console errors and unhandled promise rejections', async ({ page }, testInfo) => {
  await page.route(`${probeOrigin}/**`, (route) => route.fulfill({
    contentType: 'text/html',
    body: '<!doctype html><html><body>Diagnostic probe</body></html>',
  }))
  const diagnostics = captureBrowserDiagnostics(page, { application: 'diagnostic-probe', step: 'Emit browser errors' })
  try {
    await page.goto(`${probeOrigin}/console`)
    await page.evaluate(() => {
      console.error('Deliberate console error from the guard probe')
      console.warn('[Vue warn]: Invalid prop: deliberate guard probe')
      void Promise.reject(new Error('Deliberate unhandled rejection from the guard probe'))
    })
    await expect.poll(() => diagnostics.report().errors.map((entry) => entry.kind)).toEqual(
      expect.arrayContaining(['console.error', 'framework.warning', 'pageerror']),
    )
    expect(() => diagnostics.assertClean()).toThrow(/diagnostic-probe.*Emit browser errors/)
    expect(() => diagnostics.assertClean()).toThrow(/Deliberate unhandled rejection/)
  } finally {
    await testInfo.attach('browser-diagnostic-probe', {
      body: JSON.stringify(diagnostics.stop(), null, 2),
      contentType: 'application/json',
    })
  }
})

test('diagnostic guard observes real failed resources and an HTTP error document', async ({ page }, testInfo) => {
  await page.route(`${probeOrigin}/**`, async (route) => {
    const path = new URL(route.request().url()).pathname
    if (path === '/unavailable.png') {
      await route.abort('connectionfailed')
    } else if (path === '/missing.js') {
      await route.fulfill({ status: 404, contentType: 'application/javascript', body: '' })
    } else if (path === '/error-document') {
      await route.fulfill({ status: 503, contentType: 'text/html', body: '<!doctype html><p>Unavailable</p>' })
    } else {
      await route.fulfill({
        contentType: 'text/html',
        body: '<!doctype html><html><body><script src="/missing.js"></script><img src="/unavailable.png" alt="Probe"></body></html>',
      })
    }
  })
  const diagnostics = captureBrowserDiagnostics(page, { application: 'diagnostic-probe', step: 'Load failing resources' })
  try {
    await page.goto(`${probeOrigin}/resources`)
    await expect.poll(() => diagnostics.report().errors.some((entry) => (
      entry.kind === 'requestfailed' && entry.url?.endsWith('/unavailable.png')
    ))).toBe(true)
    await expect.poll(() => diagnostics.report().errors.some((entry) => (
      entry.kind === 'http' && entry.status === 404 && entry.resourceType === 'script'
    ))).toBe(true)

    diagnostics.setStep('Open an HTTP error document')
    await page.goto(`${probeOrigin}/error-document`)
    await expect.poll(() => diagnostics.report().errors.some((entry) => (
      entry.kind === 'http' && entry.status === 503 && entry.resourceType === 'document'
    ))).toBe(true)
    expect(() => diagnostics.assertClean()).toThrow(/HTTP 503/)
    expect(diagnostics.report().expected).toEqual([])
  } finally {
    await testInfo.attach('browser-diagnostic-probe', {
      body: JSON.stringify(diagnostics.stop(), null, 2),
      contentType: 'application/json',
    })
  }
})
