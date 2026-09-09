import { test as base } from '@playwright/test'

import {
  captureBrowserDiagnostics,
  finishBrowserDiagnostics,
  type BrowserDiagnostics,
} from './browser-diagnostics'

type DiagnosticFixtures = {
  browserDiagnostics: BrowserDiagnostics
  diagnosticApplication: string
}

export const test = base.extend<DiagnosticFixtures>({
  diagnosticApplication: ['unknown', { option: true }],
  browserDiagnostics: [async ({ page, diagnosticApplication }, use, testInfo) => {
    const diagnostics = captureBrowserDiagnostics(page, {
      application: diagnosticApplication,
      step: testInfo.title,
    })
    await diagnostics.install()
    try {
      await use(diagnostics)
    } finally {
      // Runs before Playwright closes the page, including on assertion failures.
      await finishBrowserDiagnostics(diagnostics, testInfo)
    }
  }, { auto: true }],
})

export { expect } from '@playwright/test'
