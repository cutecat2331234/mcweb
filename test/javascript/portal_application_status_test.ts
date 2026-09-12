import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

function source(path: string) {
  return readFileSync(resolve(process.cwd(), path), 'utf8')
}

test('portal application chrome preserves owned counters and status surfaces', () => {
  const layout = source('app/javascript/components/application-shell/ApplicationPortalShell.vue')
  const accountShell = source('app/javascript/shells/account.ts')
  const forumShell = source('app/javascript/shells/forum.ts')
  const storeShell = source('app/javascript/shells/store.ts')
  const announcements = source('app/javascript/components/portal/PortalAnnouncements.vue')

  assert.match(layout, /navigationBadge\(item\)/)
  assert.match(layout, /v-if="auth\.user && notifications"/)
  assert.match(layout, /shell\.applicationId === 'forum' && auth\.user && messagesUnread/)
  assert.match(layout, /shell\.applicationId === 'store' && cart/)
  assert.match(layout, /<template #icon><IconGift \/><\/template>/)
  assert.doesNotMatch(layout, /IconShoppingCart/)
  assert.match(layout, /:is="portalAnnouncements"/)
  assert.match(layout, /shell\.applicationId === 'forum' && hasPortalAnnouncements/)
  assert.doesNotMatch(layout, /import\s+PortalAnnouncements\s+from/)
  assert.doesNotMatch(layout, /import\s+FlashMessages\s+from/)
  assert.doesNotMatch(layout, /\bDrawer,/)
  assert.match(layout, /<ApplicationPortalMobileNavigation[\s\S]*?v-if="mobileNavOpen"/)
  assert.match(layout, /<LayoutSider[\s\S]*?:width="256"/)
  assert.match(layout, /:collapsed="navigationCollapsed"/)
  assert.match(layout, /width: compact \? '100%' : `calc\(100% - \$\{sidebarWidth\}px\)`/)
  assert.match(accountShell, /badgeProp: 'notifications\.unread_count'/)
  assert.match(accountShell, /labelKey: 'accountCenter\.overview', href: routes\.account/)
  assert.match(forumShell, /badgeProp: 'messages_unread\.count'/)
  assert.match(storeShell, /badgeProp: 'cart\.count'/)
  assert.match(announcements, /frontendApplicationRequestHeaders\('forum'\)/)
  assert.match(announcements, /csrfHeaders\(\)/)
  assert.match(announcements, /forumDismissAnnouncements/)
  assert.match(announcements, /notice\.dismiss_url/)
})

test('mounted application errors use the core locale while pre-i18n bootstrap keeps its fallback', () => {
  const boundary = source('app/javascript/components/ApplicationErrorBoundary.vue')
  const bootstrap = source('app/javascript/lib/createInertiaApplication.ts')
  const english = source('app/javascript/locales/en.ts')
  const chinese = source('app/javascript/locales/zh-CN.ts')

  assert.match(boundary, /t\('common\.applicationUnavailable'\)/)
  assert.match(boundary, /t\('common\.applicationUnavailableDetail'\)/)
  assert.match(boundary, /t\('common\.reloadApplication'\)/)
  assert.doesNotMatch(boundary, /Application unavailable|应用暂时不可用/)
  assert.match(bootstrap, /Application unavailable/)
  assert.match(bootstrap, /应用暂时不可用/)
  for (const locale of [english, chinese]) {
    assert.match(locale, /applicationUnavailable:/)
    assert.match(locale, /applicationUnavailableDetail:/)
    assert.match(locale, /reloadApplication:/)
  }
})

test('application error fallback does not add the UI kit to every entrypoint', () => {
  const boundary = source('app/javascript/components/ApplicationErrorBoundary.vue')

  assert.doesNotMatch(boundary, /@mcweb\/ui|@arco-design|@\/components\/ui\//)
  assert.match(boundary, /<section[^>]*role="alert"[^>]*aria-live="assertive"/)
  assert.match(boundary, /<button type="button" @click="reload">/)
  assert.match(boundary, /window\.location\.reload\(\)/)
})

test('application provider loads global dialogs only when requested and keeps their closing lifecycle', () => {
  const provider = source('app/javascript/components/AppProvider.vue')
  const prompt = source('app/javascript/components/ui/PromptDialog.vue')

  for (const kind of ['Confirm', 'Prompt']) {
    const state = `${kind.toLowerCase()}State`
    assert.doesNotMatch(provider, new RegExp(`import ${kind}Dialog from`))
    assert.match(provider, new RegExp(`\\(\\) => ${state}\\.resolve`))
    assert.match(provider, new RegExp(`if \\(!request \\|\\| ${kind}Dialog\\.value\\) return`))
    assert.match(provider, new RegExp(`await import\\('@/components/ui/${kind}Dialog\\.vue'\\)`))
    assert.match(provider, new RegExp(`<component :is="${kind}Dialog" v-if="${kind}Dialog" />`))
    assert.doesNotMatch(provider, new RegExp(`${kind}Dialog\\.value = (?:null|undefined)`))
  }
  assert.match(provider, /catch \(error\) \{\s*resolveConfirm\(false, request\)/)
  assert.match(provider, /catch \(error\) \{\s*resolvePrompt\(null, request\)/)
  assert.match(prompt, /watch\([\s\S]*?promptState\.open[\s\S]*?immediate: true/)
})

test('shared shells keep closed and breakpoint-only surfaces out of startup chunks', () => {
  const portal = source('app/javascript/components/application-shell/ApplicationPortalShell.vue')
  const identity = source('app/javascript/layouts/account/IdentityDocumentLayout.vue')
  const admin = source('app/javascript/layouts/ArcoAdminLayout.vue')
  const bootstrap = source('app/javascript/lib/createInertiaApplication.ts')
  const statusSurfaces = source('app/javascript/lib/applicationStatusSurfaces.ts')

  for (const shell of [portal, identity, admin]) {
    assert.doesNotMatch(shell, /import\s+(?:Admin)?FlashMessages\s+from/)
    assert.match(shell, /:is="flashMessages"/)
    assert.match(shell, /v-if="hasFlashMessages && flashMessages"/)
  }
  assert.doesNotMatch(admin, /import\s+PluginUiSlots\s+from/)
  assert.match(admin, /:is="pluginUiSlots"/)
  assert.match(admin, /v-if="hasPluginUiSlots && pluginUiSlots"/)
  assert.match(admin, /<ApplicationMobileDrawer[\s\S]*?v-if="mobileNavOpen"/)
  assert.match(portal, /<ApplicationPortalMobileNavigation[\s\S]*?v-if="mobileNavOpen"/)
  assert.match(statusSurfaces, /\(\) => import\('@\/components\/portal\/FlashMessages\.vue'\)/)
  assert.match(statusSurfaces, /\(\) => import\('@\/components\/admin\/AdminFlashMessages\.vue'\)/)
  assert.match(statusSurfaces, /\(\) => import\('@\/components\/plugins\/PluginUiSlots\.vue'\)/)
  assert.match(
    bootstrap,
    /createAppI18n\(initialLocale, descriptor\.locales\),\s*initialPageLoader\(\)\.then\(normalizeFrontendPageComponent\),\s*prepareApplicationStatusSurfaces\(statusSurfaceKind, applicationId, domPage\),\s*adapters\.prepare\(\)/,
  )
  assert.match(
    bootstrap,
    /pageLoad,\s*syncLocaleFromPage\(targetPage\),\s*prepareApplicationStatusSurfaces\(statusSurfaceKind, applicationId, targetPage\)/,
  )
})

test('pre-mount status chunks are declared as conditional initial budget entries', () => {
  const expectedEntries: Record<string, string[]> = {
    account: [
      'app/javascript/components/application-shell/ApplicationDeveloperModeBanner.vue',
      'app/javascript/components/portal/FlashMessages.vue',
    ],
    admin: [
      'app/javascript/components/application-shell/ApplicationDeveloperModeBanner.vue',
      'app/javascript/components/admin/AdminFlashMessages.vue',
      'app/javascript/components/plugins/PluginUiSlots.vue',
    ],
    forum: [
      'app/javascript/components/application-shell/ApplicationDeveloperModeBanner.vue',
      'app/javascript/components/portal/FlashMessages.vue',
      'app/javascript/components/portal/PortalAnnouncements.vue',
    ],
    staff: [
      'app/javascript/components/application-shell/ApplicationDeveloperModeBanner.vue',
      'app/javascript/components/portal/FlashMessages.vue',
    ],
    store: [
      'app/javascript/components/application-shell/ApplicationDeveloperModeBanner.vue',
      'app/javascript/components/portal/FlashMessages.vue',
    ],
  }

  for (const [applicationId, entries] of Object.entries(expectedEntries)) {
    const manifest = JSON.parse(source(
      `config/frontend_applications/base/${applicationId}.json`,
    )) as { budget: { conditional_initial_entries?: string[] } }
    assert.deepEqual(manifest.budget.conditional_initial_entries, entries)
  }
})

test('conditionally mounted portal flash messages retain their auto-hide lifecycle', () => {
  const flashMessages = source('app/javascript/components/portal/FlashMessages.vue')

  assert.match(flashMessages, /watch\([\s\S]*?\{ immediate: true \},\s*\)/)
  assert.match(flashMessages, /onBeforeUnmount\(clearAutoHideTimer\)/)
})

test('mobile navigation drawers expose native dialog semantics', () => {
  for (const path of [
    'app/javascript/components/application-shell/ApplicationMobileDrawer.vue',
    'app/javascript/components/application-shell/ApplicationPortalMobileNavigation.vue',
  ]) {
    const drawer = source(path)
    assert.match(drawer, /role="dialog"/)
    assert.match(drawer, /aria-modal="true"/)
    assert.match(drawer, /:aria-label=/)
  }
})
