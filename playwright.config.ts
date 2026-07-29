import { defineConfig, devices } from '@playwright/test'

const port = Number.parseInt(process.env.MCWEB_E2E_PORT || '3102', 10)
const baseURL = process.env.MCWEB_E2E_BASE_URL || `http://127.0.0.1:${port}`
const externalServer = process.env.MCWEB_E2E_EXTERNAL_SERVER === '1'

export default defineConfig({
  testDir: './test/e2e',
  outputDir: './test-results',
  fullyParallel: false,
  forbidOnly: Boolean(process.env.CI),
  retries: process.env.CI ? 1 : 0,
  workers: 1,
  reporter: process.env.CI
    ? [['line'], ['html', { outputFolder: 'playwright-report', open: 'never' }]]
    : [['list'], ['html', { outputFolder: 'playwright-report', open: 'never' }]],
  snapshotPathTemplate:
    '{testDir}/__screenshots__/{projectName}/{testFileName}/{arg}{ext}',
  expect: {
    timeout: 10_000,
    toHaveScreenshot: {
      animations: 'disabled',
      caret: 'hide',
      maxDiffPixelRatio: 0.002,
      threshold: 0.15,
    },
  },
  use: {
    baseURL,
    colorScheme: 'light',
    locale: 'en-US',
    timezoneId: 'Asia/Shanghai',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },
  webServer: externalServer
    ? undefined
    : {
        command: 'node scripts/start-system-e2e.mjs',
        url: `${baseURL}/health/ready`,
        timeout: 240_000,
        reuseExistingServer: !process.env.CI,
        stdout: 'pipe',
        stderr: 'pipe',
      },
  projects: [
    {
      name: 'desktop-chromium',
      use: {
        ...devices['Desktop Chrome'],
        viewport: { width: 1440, height: 1000 },
      },
    },
    {
      name: 'mobile-chromium',
      use: {
        ...devices['Pixel 7'],
      },
    },
  ],
})
