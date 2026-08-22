import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

const source = readFileSync(
  resolve(process.cwd(), 'app/javascript/layouts/ArcoAdminLayout.vue'),
  'utf8',
)
const css = source.match(/<style scoped>([\s\S]*?)<\/style>/)?.[1] ?? ''
const foundation = readFileSync(
  resolve(process.cwd(), 'app/javascript/styles/shell-foundation.css'),
  'utf8',
)

function rule(selector: string): string {
  const escaped = selector.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  const match = css.match(new RegExp(`${escaped}\\s*\\{([^}]*)\\}`))

  assert.ok(match, `missing responsive shell rule for ${selector}`)
  return match[1]
}

test('admin shell switches to its Drawer before the sidebar can squeeze medium viewports', () => {
  const drawerBreakpoint = css.match(/@media \(max-width: (\d+)px\)\s*\{\s*\.arco-admin-sider\s*\{\s*display: none !important;/)
  const desktopBreakpoint = css.match(/@media \(min-width: (\d+)px\)\s*\{\s*\.arco-admin-sider\s*\{\s*display: flex !important;/)

  assert.ok(drawerBreakpoint)
  assert.ok(desktopBreakpoint)
  assert.equal(Number(drawerBreakpoint[1]), 1199)
  assert.equal(Number(desktopBreakpoint[1]), 1200)

  for (const [width, expectedMode] of [
    [1280, 'sidebar'],
    [1200, 'sidebar'],
    [1199, 'drawer'],
    [1100, 'drawer'],
    [1024, 'drawer'],
    [900, 'drawer'],
    [768, 'drawer'],
    [390, 'drawer'],
  ] as const) {
    const actualMode = width <= Number(drawerBreakpoint[1]) ? 'drawer' : 'sidebar'
    assert.equal(actualMode, expectedMode, `${width}px should use the ${expectedMode}`)
  }

  assert.doesNotMatch(source, /hidden md:block/)
  assert.match(source, /class="arco-admin-mobile-menu-trigger"/)
  assert.match(source, /v-model:visible="mobileNavOpen"/)
  assert.match(source, /class="arco-admin-drawer"/)
  assert.match(source, /class="arco-admin-drawer__menu"/)
  assert.match(source, /min\(var\(--mc-shell-drawer-width, 280px\), 100vw\)/)
})

test('admin shell owns one viewport and gives main content the only page scroll container', () => {
  assert.match(rule('.arco-admin-layout'), /height:\s*100dvh/)
  assert.match(rule('.arco-admin-layout'), /min-height:\s*100dvh/)
  assert.match(rule('.arco-admin-layout'), /overflow:\s*hidden/)

  assert.match(rule('.arco-admin-body'), /min-width:\s*0/)
  assert.match(rule('.arco-admin-body'), /min-height:\s*0/)
  assert.match(rule('.arco-admin-body'), /overflow:\s*hidden/)

  assert.match(rule('.arco-admin-main'), /flex:\s*1 1 auto/)
  assert.match(rule('.arco-admin-main'), /min-width:\s*0/)
  assert.match(rule('.arco-admin-main'), /min-height:\s*0/)
  assert.match(rule('.arco-admin-main'), /overflow:\s*auto/)
  assert.match(rule('.arco-admin-main'), /overscroll-behavior:\s*contain/)

  const mainScrollContainer = source.match(/<a-layout-content\s+[\s\S]*?id="admin-content"[\s\S]*?>/)?.[0]
  assert.ok(mainScrollContainer)
  assert.match(mainScrollContainer, /class="arco-admin-main mc-page-content mc-page-surface"/)
  assert.match(mainScrollContainer, /\bscroll-region\b/)
  assert.equal((source.match(/\bscroll-region\b/g) ?? []).length, 1)

  assert.match(rule('.arco-admin-sider'), /height:\s*100%/)
  assert.match(rule('.arco-admin-sider'), /overflow:\s*hidden/)
  assert.match(rule('.arco-admin-sider__menu'), /overflow-y:\s*auto/)
  assert.match(rule('.arco-admin-drawer__menu'), /overflow-y:\s*auto/)
})

test('mobile admin navigation exposes its scroll container to keyboard users', () => {
  const drawerMenu = source.match(/<div\s+class="arco-admin-drawer__menu"[\s\S]*?>/)?.[0]

  assert.ok(drawerMenu)
  assert.match(drawerMenu, /role="navigation"/)
  assert.match(drawerMenu, /:aria-label="t\('common\.navigation'\)"/)
  assert.match(drawerMenu, /tabindex="0"/)
  assert.match(rule('.arco-admin-drawer__menu:focus-visible'), /outline:\s*2px solid rgb\(var\(--primary-6\)\)/)
  assert.match(rule('.arco-admin-drawer__menu:focus-visible'), /outline-offset:\s*-2px/)
})

test('admin header, breadcrumb, and developer warning can shrink without widening the shell', () => {
  assert.match(rule('.arco-admin-header'), /min-width:\s*0/)
  assert.match(rule('.arco-admin-header'), /flex:\s*0 0 var\(--mc-shell-topbar-height, 60px\)/)
  assert.match(rule('.arco-admin-header__left'), /flex:\s*1 1 auto/)
  assert.match(rule('.arco-admin-header__left'), /min-width:\s*0/)
  assert.match(rule('.arco-admin-header__left'), /overflow:\s*hidden/)
  assert.match(rule('.arco-admin-header__right'), /flex:\s*0 0 auto/)

  assert.match(rule('.arco-admin-breadcrumb'), /min-width:\s*0/)
  assert.match(rule('.arco-admin-breadcrumb'), /overflow:\s*hidden/)
  assert.match(css, /\.arco-admin-breadcrumb :deep\(\.arco-breadcrumb-item-label\)[\s\S]*?text-overflow:\s*ellipsis/)

  assert.match(rule('.arco-admin-developer-alert'), /flex:\s*0 0 auto/)
  assert.match(rule('.arco-admin-developer-alert'), /width:\s*auto/)
  assert.match(rule('.arco-admin-developer-alert'), /min-width:\s*0/)
  assert.match(rule('.arco-admin-developer-alert'), /max-width:\s*calc\(100% - 32px\)/)
  assert.match(css, /\.arco-admin-developer-alert :deep\(\.arco-alert-description\)[\s\S]*?overflow-wrap:\s*anywhere/)
})

test('admin shell uses tiered padding without replacing Arco structural components', () => {
  assert.match(rule('.arco-admin-main'), /padding:\s*var\(--mc-page-gutter, 24px\)/)
  assert.match(foundation, /@media \(max-width: 1279px\)[\s\S]*?--mc-page-gutter:\s*20px/)
  assert.match(foundation, /@media \(max-width: 767px\)[\s\S]*?--mc-page-gutter:\s*16px/)
  assert.match(foundation, /@media \(max-width: 479px\)[\s\S]*?--mc-page-gutter:\s*12px/)
  assert.match(css, /@media \(max-width: 767px\)[\s\S]*?\.arco-admin-main\s*\{[\s\S]*?overflow-x:\s*hidden/)

  assert.match(source, /<a-layout class="arco-admin-layout">/)
  assert.match(source, /<a-layout-sider/)
  assert.match(source, /<a-layout-header/)
  assert.match(source, /<a-layout-content/)
  assert.match(source, /<a-drawer/)
  assert.match(source, /<a-menu/)
  assert.match(css, /\.arco-admin-main :deep\(\.arco-page-header-main\)[\s\S]*?flex-direction:\s*column/)
  assert.match(css, /\.arco-admin-main :deep\(\.arco-page-header\)\s*\{[\s\S]*?box-sizing:\s*border-box/)
  assert.match(css, /\.arco-admin-main :deep\(\.arco-page-header\)\s*\{[\s\S]*?max-width:\s*100%/)
  assert.match(css, /\.arco-admin-main :deep\(\.arco-page-header-divider\)[\s\S]*?display:\s*none/)
  assert.match(css, /\.arco-admin-main :deep\(\.arco-page-header-subtitle\)[\s\S]*?white-space:\s*normal/)
  assert.match(css, /\.arco-admin-main :deep\(\.arco-table-content-scroll-x\)\s*\{\s*overflow-x:\s*auto/)
})

test('responsive shell retains Inertia navigation and current system destinations', () => {
  assert.match(source, /import \{ Link, router, usePage \} from '@inertiajs\/vue3'/)
  assert.match(source, /router\.visit\(key\)/)
  assert.match(source, /adminRoutes\.settings/)
  assert.match(source, /adminRoutes\.jobs/)
  assert.match(source, /adminRoutes\.developerWorkbench/)
  assert.doesNotMatch(source, /window\.location|location\.reload/)
})

test('admin navigation uses distinct product-area icons instead of one repeated glyph', () => {
  for (const icon of [
    'IconDashboard',
    'IconUserGroup',
    'IconHome',
    'IconMessage',
    'IconGift',
    'IconCloud',
    'IconSettings',
  ]) {
    assert.match(source, new RegExp(`icon: ${icon}`))
  }

  assert.match(source, /<component :is="group\.icon" \/>/)
  assert.doesNotMatch(source, /<template #icon><icon-apps \/><\/template>/)
})

test('expanded admin navigation keeps long labels discoverable and shares one translated brand', () => {
  assert.match(source, /:width="'var\(--mc-shell-sidebar-width, 248px\)'"/)
  assert.equal(source.match(/:title="item\.label"/g)?.length, 2)
  assert.equal(source.match(/\{\{ t\('common\.adminBrand'\) \}\}/g)?.length, 2)
  assert.doesNotMatch(source, /arco-admin-brand__text">McWeb Admin</)
})

test('collapsed sidebar keeps its brand and menu inside the 48px rail', () => {
  assert.match(
    css,
    /\.arco-admin-sider\.arco-layout-sider-collapsed \.arco-admin-brand\s*\{[\s\S]*?padding-inline:\s*7px/,
  )
  assert.match(
    css,
    /\.arco-admin-sider\.arco-layout-sider-collapsed \.arco-admin-sider__menu\s*\{[\s\S]*?padding-inline:\s*4px/,
  )
})

test('desktop navigation persists collapse state and keeps one visible menu group', () => {
  assert.match(source, /COLLAPSED_STORAGE_KEY = 'mc-admin-arco-nav-collapsed'/)
  assert.match(source, /readStoredCollapsedState\(\)/)
  assert.match(source, /watch\(collapsed, persistCollapsedState\)/)
  assert.match(source, /openKeys\.value = nextKey \? \[nextKey\] : \[\]/)
  assert.equal(source.match(/:open-keys="openKeys"/g)?.length, 2)
  assert.equal(source.match(/@update:open-keys="onOpenKeysChange"/g)?.length, 2)
  assert.doesNotMatch(source, /v-model:open-keys/)
  assert.doesNotMatch(source, /mc-admin-arco-nav-open/)
})

test('route changes open and reveal the selected item in both navigation surfaces', () => {
  assert.match(source, /watch\(\s*\[activeGroupKey, activeItemHref\]/)
  assert.match(source, /openKeys\.value = groupKey \? \[groupKey\] : \[\]/)
  assert.match(source, /querySelector<HTMLElement>\('\.arco-menu-selected'\)/)
  assert.match(source, /scrollIntoView\(\{ block: 'nearest' \}\)/)
  assert.match(source, /ref="desktopMenuScroll"/)
  assert.match(source, /ref="drawerMenuScroll"/)
})
