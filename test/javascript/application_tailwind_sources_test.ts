import assert from 'node:assert/strict'
import { existsSync, readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import test from 'node:test'

function source(path: string) {
  return readFileSync(resolve(process.cwd(), path), 'utf8')
}

const applicationStyles = new Map([
  ['account.css', ['../../pages/Account', '../../pages/Identity', '../../pages/Minecraft']],
  ['admin.css', [
    '../../pages/Admin',
    '../../layouts/ArcoAdminLayout.vue',
    '../../components/admin',
    '../../components/plugins',
  ]],
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

const portalApplicationUiComponents = new Map([
  ['account.css', [
    'Alert', 'Badge', 'Button', 'Checkbox', 'ConfirmDialog', 'Input', 'Label',
    'PromptDialog', 'Select', 'Table', 'TableBody', 'TableCell', 'TableHead',
    'TableHeader', 'TableRow', 'Textarea',
  ]],
  ['forum.css', [
    'Alert', 'Avatar', 'Badge', 'Button', 'Checkbox', 'ConfirmDialog',
    'FileInput', 'Input', 'Label', 'PromptDialog', 'Select', 'Table', 'TableBody',
    'TableCell', 'TableHead', 'TableHeader', 'TableRow', 'Textarea',
  ]],
  ['staff.css', ['Button', 'ConfirmDialog', 'Input', 'PromptDialog']],
  ['store.css', [
    'Badge', 'Button', 'Card', 'CardContent', 'Checkbox', 'ConfirmDialog',
    'FileInput', 'Input', 'Label', 'PromptDialog', 'Radio', 'Select', 'Table',
    'TableBody', 'TableCell', 'TableHead', 'TableHeader', 'TableRow', 'Textarea',
  ]],
])

test('each Tailwind application root scans only its declared source surface', () => {
  for (const [name, requiredSources] of applicationStyles) {
    const stylesheetPath = resolve(
      process.cwd(),
      `app/javascript/styles/applications/${name}`,
    )
    const stylesheet = readFileSync(stylesheetPath, 'utf8')

    assert.match(stylesheet, /^@import "tailwindcss" source\(none\);/)
    assert.doesNotMatch(stylesheet, /@source\s+[^"']/)
    assert.doesNotMatch(stylesheet, /@source\s+["']\.\.\/\.\.\/pages["']/)
    assert.doesNotMatch(stylesheet, /@source\s+["'][^"']*\/ee\//)
    assert.doesNotMatch(stylesheet, /@source\s+["'][^"']*\/pvp\//)
    const uiComponents = portalApplicationUiComponents.get(name)
    if (uiComponents) {
      assert.doesNotMatch(
        stylesheet,
        /@source\s+["']\.\.\/\.\.\/components\/ui["']/,
        `${name}: scan only the UI primitives reachable through AppProvider`,
      )
      for (const component of uiComponents) {
        assert.match(
          stylesheet,
          new RegExp(`@source ["']\\.\\.\\/\\.\\.\\/components\\/ui\\/${component}\\.vue["'];`),
        )
      }
    }
    for (const path of requiredSources) {
      assert.match(stylesheet, new RegExp(`@source ["']${path.replaceAll('/', '\\/')}["'];`))
    }
    for (const match of stylesheet.matchAll(/@source\s+["']([^"']+)["'];/g)) {
      assert.equal(
        existsSync(resolve(dirname(stylesheetPath), match[1])),
        true,
        `${name}: @source target does not exist: ${match[1]}`,
      )
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

test('account Tailwind sources exclude forum-only announcement content', () => {
  const account = source('app/javascript/styles/applications/account.css')

  assert.doesNotMatch(account, /components\/portal\/PortalAnnouncements\.vue/)
})

test('store Tailwind sources include the shared breadcrumb used by commerce pages', () => {
  const store = source('app/javascript/styles/applications/store.css')

  assert.match(store, /@source "\.\.\/\.\.\/components\/portal\/Breadcrumb\.vue";/)
})
