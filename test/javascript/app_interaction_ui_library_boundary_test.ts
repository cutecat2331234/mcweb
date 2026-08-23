import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

const migratedInteractionPages = [
  'app/javascript/pages/Commerce/Categories/Show.vue',
  'app/javascript/pages/Commerce/Orders/Index.vue',
  'app/javascript/pages/Commerce/Wishlist/Index.vue',
  'app/javascript/pages/Community/Drafts/Edit.vue',
  'app/javascript/pages/Community/Messages/Index.vue',
  'app/javascript/pages/Community/Messages/New.vue',
  'app/javascript/pages/Community/Messages/Show.vue',
  'app/javascript/pages/Community/Search/Index.vue',
  'app/javascript/pages/Community/Topics/New.vue',
  'app/javascript/pages/Community/Topics/Show.vue',
  'app/javascript/pages/Community/Unread/Index.vue',
  'app/javascript/pages/Community/Users/Show.vue',
]

function source(path: string) {
  return readFileSync(resolve(process.cwd(), path), 'utf8')
}

test('forum and commerce interaction controls use the shared Arco entrypoint', () => {
  for (const path of migratedInteractionPages) {
    const page = source(path)

    assert.match(page, /from '@mcweb\/ui'/, path)
    assert.doesNotMatch(page, /<(?:button|select|textarea)\b/i, path)
    assert.doesNotMatch(page, /<Button\b[^>]*\bsize="xs"/i, path)
  }
})

test('the legacy button wrapper does not grow product-specific size variants', () => {
  const button = source('app/javascript/components/ui/Button.vue')

  assert.doesNotMatch(button, /\bxs:\s*['"]/)
})
