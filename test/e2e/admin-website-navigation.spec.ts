import { expect, test, type Page, type Request } from '@playwright/test'
import { acceptanceAuthStatePath } from './support/auth-state'

const destinations = [
  {
    path: '/admin/website/pages',
    title: 'Website pages',
    component: 'Admin/Generic/Index',
  },
  {
    path: '/admin/website/articles',
    title: 'Website articles',
    component: 'Admin/Generic/Index',
    // Pages and articles share a component. Check that a menu visit updates
    // its props as well as opening destinations with different components.
    sourcePath: '/admin/website/pages',
    sourceTitle: 'Website pages',
  },
  {
    path: '/admin/website/nav_items',
    title: 'Navigation',
    component: 'Admin/Website/NavItems/Index',
  },
  {
    path: '/admin/website/recycle-bin',
    title: 'Recycle bin',
    component: 'Admin/Website/Recovery/Index',
  },
  {
    path: '/admin/website/themes',
    title: 'Website themes',
    component: 'Admin/Generic/Index',
  },
]

function diagnosticUrl(value: string) {
  try {
    const url = new URL(value)
    // Do not attach query strings, fragments, or credentials to the report.
    return `${url.origin}${url.pathname}`
  } catch {
    return '(unavailable)'
  }
}

function requestSummary(request: Request) {
  return {
    method: request.method(),
    url: diagnosticUrl(request.url()),
    resourceType: request.resourceType(),
  }
}

function captureDiagnostics(page: Page) {
  type RequestSummary = ReturnType<typeof requestSummary>
  type ResponseSummary = RequestSummary & { status: number; inertia: string | null }
  const diagnostics = {
    consoleErrors: [] as Array<{ message: string; url: string }>,
    pageErrors: [] as string[],
    failedRequests: [] as Array<RequestSummary & { error: string }>,
    httpErrors: [] as ResponseSummary[],
    cmsResponses: [] as ResponseSummary[],
  }

  page.on('console', (message) => {
    if (message.type() === 'error') {
      diagnostics.consoleErrors.push({
        message: message.text(),
        url: diagnosticUrl(message.location().url),
      })
    }
  })
  page.on('pageerror', (error) => {
    diagnostics.pageErrors.push(error.stack || error.message)
  })
  page.on('requestfailed', (request) => {
    diagnostics.failedRequests.push({
      ...requestSummary(request),
      error: request.failure()?.errorText || 'Unknown request failure',
    })
  })
  page.on('response', (response) => {
    const summary = {
      ...requestSummary(response.request()),
      status: response.status(),
      inertia: response.headers()['x-inertia'] || null,
    }
    if (summary.status >= 400) diagnostics.httpErrors.push(summary)
    if (new URL(response.url()).pathname.startsWith('/admin/website/')) {
      diagnostics.cmsResponses.push(summary)
    }
  })

  return diagnostics
}

async function openWebsiteMenu(page: Page, isMobile: boolean) {
  if (isMobile) {
    await page.locator('.arco-admin-mobile-menu-trigger').click()
  } else {
    const sider = page.locator('.arco-admin-sider')
    if ((await sider.getAttribute('class'))?.includes('arco-layout-sider-collapsed')) {
      await page.locator('.arco-admin-collapse-trigger').click()
    }
  }

  const navigation = page.locator(
    isMobile ? '.arco-admin-drawer__menu' : '.arco-admin-sider__menu',
  )
  await expect(navigation).toBeVisible()
  const group = navigation.locator('.arco-admin-nav-group--website')
  await expect(group).toBeVisible()
  const content = group.locator('.arco-menu-inline-content')
  if (!(await content.isVisible())) {
    await group.locator('.arco-menu-inline-header').click()
  }
  await expect(content).toBeVisible()
  return group
}

test.use({ storageState: acceptanceAuthStatePath('owner') })

for (const destination of destinations) {
  test(`website menu opens ${destination.path} without a document reload`, async ({ page, isMobile }, testInfo) => {
    const diagnostics = captureDiagnostics(page)
    try {
      const sourcePath = destination.sourcePath || '/admin/system/jobs'
      const sourceTitle = destination.sourceTitle || 'Background jobs'
      const initialResponse = await page.goto(`${sourcePath}?locale=en`)
      expect(initialResponse?.status(), 'the source Admin page must load').toBe(200)
      await expect(page).toHaveURL((url) => url.pathname === sourcePath)

      const shell = page.locator('.arco-admin-layout')
      const heading = page.locator('#admin-content .arco-page-header-title')
      await expect(shell).toBeVisible()
      await expect(heading).toHaveText(sourceTitle)
      const marker = crypto.randomUUID()
      await page.locator('html').evaluate((element, value) => {
        ;(element as HTMLElement).dataset.acceptanceCmsDocumentMarker = value
      }, marker)
      await shell.evaluate((element, value) => {
        ;(element as HTMLElement).dataset.acceptanceCmsShellMarker = value
      }, marker)

      const menu = await openWebsiteMenu(page, isMobile)
      const item = menu.locator(`[data-prefetch-href="${destination.path}"]`)
      await expect(item).toBeVisible()
      const [response] = await Promise.all([
        page.waitForResponse((candidate) => (
          candidate.request().method() === 'GET'
          && new URL(candidate.url()).pathname === destination.path
        )),
        item.click(),
      ])

      expect(response.status(), 'CMS menu response status').toBe(200)
      expect(response.request().headers()['x-inertia'], 'CMS menu request is an Inertia visit').toBe('true')
      expect(response.headers()['x-inertia'], 'CMS response remains in the Admin application').toBe('true')
      const payload = await response.json()
      // Assert only the fields needed by this contract; never attach the full
      // Inertia payload, which also contains authentication and CSRF props.
      expect(payload.component, 'CMS Inertia component').toBe(destination.component)
      expect(payload.props?.title, 'CMS server title').toBe(destination.title)
      await expect(page).toHaveURL((url) => url.pathname === destination.path)
      await expect(heading).toHaveText(destination.title)
      await expect(heading).toBeVisible()
      await expect(page.locator('.mc-application-error')).toHaveCount(0)
      await expect(page.locator('html')).toHaveAttribute('data-mcweb-application', 'admin')
      await expect(page.locator('html')).toHaveAttribute('data-acceptance-cms-document-marker', marker)
      await expect(shell).toHaveAttribute('data-acceptance-cms-shell-marker', marker)

      if (isMobile) {
        await expect(page.locator('.arco-admin-drawer')).not.toBeVisible()
      } else {
        await expect(item).toHaveClass(/arco-menu-selected/)
      }

      expect(diagnostics.consoleErrors, 'CMS console errors').toEqual([])
      expect(diagnostics.pageErrors, 'CMS uncaught page errors').toEqual([])
      expect(diagnostics.failedRequests, 'CMS failed network requests').toEqual([])
      expect(diagnostics.httpErrors, 'CMS HTTP errors').toEqual([])
    } finally {
      // Keep diagnostics even when clicking, loading, or rendering times out.
      await testInfo.attach('website-navigation-diagnostics', {
        body: JSON.stringify({ destination: destination.path, ...diagnostics }, null, 2),
        contentType: 'application/json',
      })
    }
  })
}
