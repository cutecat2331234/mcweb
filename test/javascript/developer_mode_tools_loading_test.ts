import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import test from 'node:test'

const projectRoot = fileURLToPath(new URL('../../', import.meta.url))

for (const layout of [
  'account/IdentityDocumentLayout.vue',
  'PortalLayout.vue',
  'WebsiteLayout.vue',
]) {
  test(`${layout} keeps developer-only UI out of the normal route graph`, () => {
    const source = readFileSync(
      `${projectRoot}/app/javascript/layouts/${layout}`,
      'utf8',
    )

    assert.match(source, /defineAsyncComponent\(\s*\(\)\s*=>\s*import\(['"]@\/components\/portal\/DeveloperModeTools\.vue['"]\)/)
    assert.match(source, /__MCWEB_DEVELOPER_BUILD__/)
    assert.match(source, /:is="DeveloperModeTools"/)
    assert.match(source, /v-if="DeveloperModeTools && developerMode\.enabled"/)
    assert.doesNotMatch(source, /import\s+DeveloperModeTools\s+from/)
  })
}
