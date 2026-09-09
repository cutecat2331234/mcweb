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
  assert.match(layout, /<PortalAnnouncements/)
  assert.match(layout, /<LayoutSider[\s\S]*?:width="248"/)
  assert.match(layout, /marginLeft: compact \? '0' : 'var\(--mc-shell-sidebar-width, 248px\)'/)
  assert.match(layout, /width: compact \? '100%' : 'calc\(100% - var\(--mc-shell-sidebar-width, 248px\)\)'/)
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
