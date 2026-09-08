import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

function source(path: string) {
  return readFileSync(resolve(process.cwd(), path), 'utf8')
}

const applicationStyles = new Map([
  ['account.css', ['../../pages/Account', '../../pages/Identity', '../../pages/Minecraft']],
  ['forum.css', ['../../pages/Community']],
  ['staff.css', [
    '../../pages/Staff/Dashboard',
    '../../pages/Staff/Forum/Approvals',
    '../../pages/Staff/ModerationCases',
    '../../pages/Staff/ReportAppeals',
  ]],
  ['store.css', ['../../pages/Commerce', '../../pages/Payments']],
  ['website.css', ['../../pages/Website', '../../pages/Plugins']],
  ['website-preview.css', [
    '../../pages/Website/Pages/Show.vue',
    '../../pages/Website/Articles/Show.vue',
    '../../pages/WebsitePreview',
  ]],
])

test('each Tailwind application root scans only its declared source surface', () => {
  for (const [name, requiredSources] of applicationStyles) {
    const stylesheet = source(`app/javascript/styles/applications/${name}`)

    assert.match(stylesheet, /^@import "tailwindcss" source\(none\);/)
    assert.doesNotMatch(stylesheet, /@source\s+[^"']/)
    assert.doesNotMatch(stylesheet, /@source\s+["']\.\.\/\.\.\/pages["']/)
    assert.doesNotMatch(stylesheet, /@source\s+["'][^"']*\/ee\//)
    assert.doesNotMatch(stylesheet, /@source\s+["'][^"']*\/pvp\//)
    for (const path of requiredSources) {
      assert.match(stylesheet, new RegExp(`@source ["']${path.replaceAll('/', '\\/')}["'];`))
    }
  }
})

test('shared style primitives never trigger repository-wide Tailwind detection', () => {
  for (const path of [
    'app/javascript/styles/app-shell.css',
    'app/javascript/styles/website.css',
  ]) {
    assert.doesNotMatch(source(path), /@import\s+["']tailwindcss["']/)
  }
})
