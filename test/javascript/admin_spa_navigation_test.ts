import assert from 'node:assert/strict'
import { readFileSync, readdirSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'
import {
  isPlainPrimaryClick,
  resolveAdminSpaHref,
} from '../../app/javascript/lib/adminNavigation.ts'

const root = process.cwd()

function source(relativePath: string) {
  return readFileSync(new URL(`../../${relativePath}`, import.meta.url), 'utf8')
}

function adminVueSources() {
  const pagesRoot = resolve(root, 'app/javascript/pages/Admin')
  const pages = readdirSync(pagesRoot, { recursive: true, encoding: 'utf8' })
    .filter((relativePath) => relativePath.endsWith('.vue'))
    .map((relativePath) => ({
      path: `app/javascript/pages/Admin/${relativePath.replaceAll('\\', '/')}`,
      source: readFileSync(resolve(pagesRoot, relativePath), 'utf8'),
    }))

  return [
    {
      path: 'app/javascript/layouts/ArcoAdminLayout.vue',
      source: source('app/javascript/layouts/ArcoAdminLayout.vue'),
    },
    ...pages,
  ]
}

function openingTags(sourceText: string): string[] {
  const tags: string[] = []
  let cursor = 0

  while (cursor < sourceText.length) {
    const start = sourceText.indexOf('<', cursor)
    if (start === -1) break

    const tagName = sourceText.slice(start + 1).match(/^[A-Za-z][\w-]*/)
    if (!tagName) {
      cursor = start + 1
      continue
    }

    let quote: '"' | "'" | null = null
    let end = start + tagName[0].length + 1
    for (; end < sourceText.length; end += 1) {
      const character = sourceText[end]
      if (quote) {
        if (character === quote) quote = null
      } else if (character === '"' || character === "'") {
        quote = character
      } else if (character === '>') {
        tags.push(sourceText.slice(start, end + 1))
        break
      }
    }

    cursor = end + 1
  }

  return tags
}

function hrefValue(tag: string): string | null {
  const match = tag.match(/\s:?href\s*=\s*(?:"([^"]*)"|'([^']*)')/)
  return match?.[1] ?? match?.[2] ?? null
}

const currentHref = 'https://mcweb.test/admin/users?page=2'

test('same-origin admin destinations stay inside the Inertia admin entry', () => {
  assert.equal(
    resolveAdminSpaHref({
      href: '/admin/forum/topics?status=open#results',
      currentHref,
    }),
    '/admin/forum/topics?status=open#results',
  )
  assert.equal(
    resolveAdminSpaHref({
      href: 'https://mcweb.test/admin',
      currentHref,
    }),
    '/admin',
  )
  assert.equal(
    resolveAdminSpaHref({
      href: '/admin/system/jobs',
      currentHref,
    }),
    '/admin/system/jobs',
  )
})

test('cross-entry, external, download, new-tab, and explicit hard destinations stay native', () => {
  for (const options of [
    { href: '/', currentHref },
    { href: '/app/forum/sections', currentHref },
    { href: '/administrator', currentHref },
    { href: 'https://example.com/admin/users', currentHref },
    { href: '/admin/export.csv', currentHref, download: true },
    { href: '/admin/users', currentHref, target: '_blank' },
    { href: '/admin/website/pages/preview', currentHref, hardNavigation: true },
  ]) {
    assert.equal(resolveAdminSpaHref(options), null)
  }
})

test('same-document anchors and modified clicks retain browser behavior', () => {
  assert.equal(
    resolveAdminSpaHref({
      href: '#details',
      currentHref,
    }),
    null,
  )

  assert.equal(
    isPlainPrimaryClick({
      button: 0,
      ctrlKey: false,
      metaKey: false,
      shiftKey: false,
      altKey: false,
    }),
    true,
  )
  assert.equal(
    isPlainPrimaryClick({
      button: 0,
      ctrlKey: true,
      metaKey: false,
      shiftKey: false,
      altKey: false,
    }),
    false,
  )
  assert.equal(
    isPlainPrimaryClick({
      button: 1,
      ctrlKey: false,
      metaKey: false,
      shiftKey: false,
      altKey: false,
    }),
    false,
  )
})

test('admin entry installs delegated SPA navigation and preserves intentional hard boundaries', () => {
  const entry = source('app/javascript/entrypoints/admin.ts')
  const layout = source('app/javascript/layouts/ArcoAdminLayout.vue')
  const settings = source('app/javascript/pages/Admin/System/Settings/Show.vue')
  const genericIndex = source('app/javascript/pages/Admin/Generic/Index.vue')
  const orderIndex = source('app/javascript/pages/Admin/Store/Orders/IndexProDemo.vue')

  assert.match(entry, /installAdminSpaNavigation\(\(href\) => router\.visit\(href\)\)/)
  assert.match(layout, /href: adminRoutes\.jobs/)
  assert.doesNotMatch(layout, /window\.location\.assign\(key\)/)
  assert.doesNotMatch(layout, /<Link :href="adminRoutes\.site"/)
  assert.match(settings, /function visitEntry\(url: string\)/)
  assert.match(settings, /router\.visit\(url\)/)
  assert.doesNotMatch(settings, /data-admin-hard-navigation/)
  assert.match(genericIndex, /v-if="exportUrl"[\s\S]*data-admin-hard-navigation/)
  assert.match(orderIndex, /v-if="exportUrl"[^>]*data-admin-hard-navigation/)
})

test('admin source keeps internal links on Inertia and explicitly inventories every hard boundary', () => {
  const hardDestinations: string[] = []

  for (const page of adminVueSources()) {
    for (const tag of openingTags(page.source)) {
      const href = hrefValue(tag)
      if (href === null) continue

      const tagName = tag.match(/^<([A-Za-z][\w-]*)/)?.[1]
      if (tagName === 'Link') continue
      if (tagName === 'a' && href.startsWith('#')) continue

      assert.match(
        tag,
        /\sdata-admin-hard-navigation(?:\s|>|=)/,
        `${page.path} uses a non-Inertia href without an explicit hard-navigation boundary: ${tag}`,
      )
      hardDestinations.push(`${page.path}|${href}`)
    }
  }

  assert.deepEqual(
    hardDestinations.sort(),
    [
      'app/javascript/layouts/ArcoAdminLayout.vue|adminRoutes.site',
      'app/javascript/layouts/ArcoAdminLayout.vue|adminRoutes.site',
      'app/javascript/pages/Admin/Dashboard/Index.vue|adminRoutes.site',
      'app/javascript/pages/Admin/Forum/Attachments/Index.vue|record.post_url',
      'app/javascript/pages/Admin/Forum/Attachments/Index.vue|upload.post_url',
      'app/javascript/pages/Admin/Frontend/Templates/Index.vue|/template-starter/manifest.json',
      'app/javascript/pages/Admin/Frontend/Templates/Index.vue|starterDownloadUrl',
      'app/javascript/pages/Admin/Frontend/Templates/Index.vue|template.preview_portal_url',
      'app/javascript/pages/Admin/Frontend/Templates/Index.vue|template.preview_website_url',
      'app/javascript/pages/Admin/Generic/Index.vue|action.href',
      'app/javascript/pages/Admin/Generic/Index.vue|exportUrl',
      'app/javascript/pages/Admin/Generic/Index.vue|record.url',
      'app/javascript/pages/Admin/Generic/Show.vue|action.href',
      'app/javascript/pages/Admin/Store/Orders/IndexProDemo.vue|exportUrl',
      'app/javascript/pages/Admin/System/Jobs/Index.vue|dashboardUrl',
    ].sort(),
  )
})

test('native admin forms always prevent browser submission', () => {
  for (const page of adminVueSources()) {
    for (const tag of openingTags(page.source)) {
      if (!/^<form(?:\s|>)/.test(tag)) continue

      assert.match(
        tag,
        /\s@submit\.prevent(?:\s|=)/,
        `${page.path} contains a native form that can reload the document: ${tag}`,
      )
      assert.doesNotMatch(
        tag,
        /\saction\s*=/,
        `${page.path} contains a native form action instead of an Inertia request: ${tag}`,
      )
    }
  }
})

test('admin pages share one persistent shell and cross-entry links stay outside Inertia', () => {
  const demo = source('app/javascript/pages/Admin/ArcoDemo/Index.vue')
  const dashboard = source('app/javascript/pages/Admin/Dashboard/Index.vue')
  const attachments = source('app/javascript/pages/Admin/Forum/Attachments/Index.vue')
  const genericIndex = source('app/javascript/pages/Admin/Generic/Index.vue')
  const genericShow = source('app/javascript/pages/Admin/Generic/Show.vue')

  assert.match(demo, /import AdminLayout from '@\/layouts\/AdminLayout\.vue'/)
  assert.match(demo, /defineOptions\(\{ layout: AdminLayout \}\)/)
  assert.match(dashboard, /:href="adminRoutes\.site"[\s\S]*data-admin-hard-navigation/)
  assert.match(attachments, /:href="record\.post_url"[\s\S]*target="_blank"/)
  assert.match(genericIndex, /isAdminSpaNavigationHref\(record\.url\)/)
  assert.match(genericShow, /!action\.external && isAdminSpaNavigationHref\(action\.href\)/)
})

test('website previews deliberately use the public Inertia entry', () => {
  const pagesController = source('app/controllers/admin/website/pages_controller.rb')
  const articlesController = source('app/controllers/admin/website/articles_controller.rb')

  assert.match(
    pagesController,
    /render inertia: "Website\/Pages\/Show", layout: "inertia", props:/,
  )
  assert.match(
    articlesController,
    /render inertia: "Website\/Articles\/Show", layout: "inertia", props:/,
  )
})
