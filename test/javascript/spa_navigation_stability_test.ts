import assert from 'node:assert/strict'
import { readFileSync, readdirSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

const root = process.cwd()

function source(path: string): string {
  return readFileSync(resolve(root, path), 'utf8')
}

function vueSourcesUnder(path: string): Array<{ path: string; source: string }> {
  const absoluteRoot = resolve(root, path)

  return readdirSync(absoluteRoot, { recursive: true, encoding: 'utf8' })
    .filter((relativePath) => relativePath.endsWith('.vue'))
    .map((relativePath) => ({
      path: relativePath.replaceAll('\\', '/'),
      source: readFileSync(resolve(absoluteRoot, relativePath), 'utf8'),
    }))
}

function openingTags(sourceText: string, tagName: string): string[] {
  const tags: string[] = []
  const needle = `<${tagName}`
  let cursor = 0

  while (cursor < sourceText.length) {
    const start = sourceText.indexOf(needle, cursor)
    if (start === -1) break

    let quote: '"' | "'" | null = null
    let end = start + needle.length

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

test('confirmed same-entry links use Inertia navigation', () => {
  const productPreview = source('app/javascript/pages/Commerce/Products/Preview.vue')
  const systemSettings = source('app/javascript/pages/Admin/System/Settings/Show.vue')

  assert.match(productPreview, /import \{ Link, router \} from '@inertiajs\/vue3'/)
  assert.match(productPreview, /<Link :href="routes\.signIn"/)
  assert.doesNotMatch(productPreview, /<a :href="routes\.signIn"/)

  assert.match(systemSettings, /import \{ Link, router, useForm \} from '@inertiajs\/vue3'/)
  assert.match(systemSettings, /<Link/)
  assert.match(systemSettings, /:href="entry\.url"/)
  assert.match(systemSettings, /function visitEntry\(url: string\)/)
  assert.match(systemSettings, /if \(url === window\.location\.pathname\) return/)
  assert.match(systemSettings, /router\.visit\(url\)/)
  assert.match(systemSettings, /@click="visitEntry\(entry\.url\)"/)
  assert.doesNotMatch(systemSettings, /<a(?:-link)?[^>]+href="\/health\/ready"/)
})

test('priority community views do not fall back to document-level navigation', () => {
  const priorityPaths = [
    'app/javascript/pages/Community/Drafts',
    'app/javascript/pages/Community/Messages',
    'app/javascript/pages/Community/Sections',
    'app/javascript/pages/Community/Users',
  ]

  for (const path of priorityPaths) {
    for (const page of vueSourcesUnder(path)) {
      assert.doesNotMatch(
        page.source,
        /window\.location(?:\s*=|\.href\s*=|\.assign\(|\.replace\(|\.reload\()/,
        `${path}/${page.path} must not force a document reload`,
      )
    }
  }

  const hoverCard = source('app/javascript/components/portal/UserHoverCard.vue')
  assert.match(hoverCard, /<Link :href="card\.profile_url"/)
  assert.match(hoverCard, /<Link v-if="card\.message_url" :href="card\.message_url"/)
})

test('native forms are prevented unless they contain only explicit button-driven actions', () => {
  const orders = source('app/javascript/pages/Commerce/Orders/Show.vue')
  const sources = vueSourcesUnder('app/javascript')

  for (const file of sources) {
    const formTags = openingTags(file.source, 'form')
    for (const tag of formTags) {
      if (tag.includes('@submit.prevent')) continue

      assert.equal(
        file.path,
        'pages/Commerce/Orders/Show.vue',
        `${file.path} contains a native form without @submit.prevent: ${tag}`,
      )
      assert.match(tag, /order\.payment_providers\.length > 1/)
    }
  }

  assert.match(orders, /<Button type="button" @click="payForm\.post\(routes\.storeCheckout\)"/)
})

test('document reload APIs are not used for ordinary application navigation', () => {
  for (const file of vueSourcesUnder('app/javascript')) {
    assert.doesNotMatch(
      file.source,
      /window\.location(?:\s*=|\.href\s*=|\.assign\(|\.replace\(|\.reload\()/,
      `${file.path} must not mutate window.location`,
    )
  }
})

test('explicit document-navigation boundaries remain native links', () => {
  const adminLayout = source('app/javascript/layouts/ArcoAdminLayout.vue')
  const order = source('app/javascript/pages/Commerce/Orders/Show.vue')

  assert.match(adminLayout, /<a :href="adminRoutes\.site"/)
  assert.match(order, /<a :href="order\.receipt_url" target="_blank"/)
  assert.match(order, /<a :href="order\.receipt_pdf_url"/)
})
