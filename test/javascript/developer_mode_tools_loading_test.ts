import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import test from 'node:test'

const projectRoot = fileURLToPath(new URL('../../', import.meta.url))

for (const layout of ['AuthLayout.vue', 'PortalLayout.vue', 'WebsiteLayout.vue']) {
  test(`${layout} keeps developer-only UI out of the normal route graph`, () => {
    const source = readFileSync(
      `${projectRoot}/app/javascript/layouts/${layout}`,
      'utf8',
    )

    assert.match(source, /defineAsyncComponent\(\s*\(\)\s*=>\s*import\(['"]@\/components\/portal\/DeveloperModeTools\.vue['"]\)/)
    assert.match(source, /<DeveloperModeTools\s+v-if="developerMode\.enabled"\s*\/>/)
    assert.doesNotMatch(source, /import\s+DeveloperModeTools\s+from/)
  })
}
