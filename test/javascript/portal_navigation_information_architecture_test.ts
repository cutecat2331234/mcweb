import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

function source(path: string) {
  return readFileSync(resolve(process.cwd(), path), 'utf8')
}

const portalNav = source('app/javascript/lib/usePortalNav.ts')
const portalSidebar = source('app/javascript/components/portal/PortalSidebar.vue')

test('forum navigation stays focused on public browsing instead of embedding every personal tool', () => {
  assert.match(portalNav, /key: 'forum-browse'/)
  assert.doesNotMatch(portalNav, /key: 'forum-mine'/)
  assert.doesNotMatch(portalNav, /const forumPersonalItems/)
  assert.match(portalNav, /key: 'portal-personal'[\s\S]*href: routes\.account/)
})

test('the site-wide staff workspace is a separate permission-gated destination', () => {
  assert.match(portalNav, /if \(opts\.value\.staffWorkspace\)/)
  assert.match(
    portalNav,
    /key: 'portal-staff'[\s\S]*href: opts\.value\.staffWorkspace\.url[\s\S]*badge: opts\.value\.staffWorkspace\.count/,
  )
  assert.match(portalSidebar, /staffWorkspace\?: \{ count: number; url: string;/)
  assert.match(portalSidebar, /staffWorkspace: props\.staffWorkspace/)
})
