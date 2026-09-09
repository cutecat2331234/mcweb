import type { Page } from '@playwright/test'
import { expect, test } from './support/fixtures'
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

test.use({ storageState: acceptanceAuthStatePath('owner'), diagnosticApplication: 'admin' })

for (const destination of destinations) {
  test(`website menu opens ${destination.path} without a document reload`, async ({ page, isMobile, browserDiagnostics }) => {
    const sourcePath = destination.sourcePath || '/admin/system/jobs'
    const sourceTitle = destination.sourceTitle || 'Background jobs'
    browserDiagnostics.setStep(`Open CMS navigation source ${sourcePath}`)
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

    browserDiagnostics.setStep(`Open the website menu for ${destination.path}`)
    const menu = await openWebsiteMenu(page, isMobile)
    const item = menu.locator(`[data-prefetch-href="${destination.path}"]`)
    await expect(item).toBeVisible()
    browserDiagnostics.setStep(`Visit ${destination.path} through the CMS menu`)
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
  })
}
