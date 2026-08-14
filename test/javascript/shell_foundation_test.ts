import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

const foundation = readFileSync(
  resolve(process.cwd(), 'app/javascript/styles/shell-foundation.css'),
  'utf8',
)
const adminEntry = readFileSync(
  resolve(process.cwd(), 'app/javascript/entrypoints/admin.ts'),
  'utf8',
)
const appEntry = readFileSync(
  resolve(process.cwd(), 'app/javascript/entrypoints/inertia.ts'),
  'utf8',
)
const adminLayout = readFileSync(
  resolve(process.cwd(), 'app/javascript/layouts/ArcoAdminLayout.vue'),
  'utf8',
)
const staffLayout = readFileSync(
  resolve(process.cwd(), 'app/javascript/layouts/StaffLayout.vue'),
  'utf8',
)

test('admin and application entrypoints load one shared shell geometry contract', () => {
  for (const entrypoint of [adminEntry, appEntry]) {
    assert.match(entrypoint, /import '@\/styles\/shell-foundation\.css'/)
  }

  for (const token of [
    '--mc-shell-topbar-height',
    '--mc-shell-sidebar-width',
    '--mc-shell-drawer-width',
    '--mc-page-max-width',
    '--mc-page-gutter',
    '--mc-space-4',
    '--mc-type-page-title-line-height',
    '--mc-type-page-subtitle-line-height',
  ]) {
    assert.match(foundation, new RegExp(`${token}:`))
  }
})

test('admin and staff shells consume shared geometry instead of edition-local measurements', () => {
  for (const layout of [adminLayout, staffLayout]) {
    assert.match(layout, /var\(--mc-shell-sidebar-width, 248px\)/)
    assert.match(layout, /mc-shell-header/)
    assert.match(layout, /mc-page-content mc-page-surface/)
    assert.match(layout, /mc-page-container/)
    assert.match(layout, /var\(--mc-page-gutter, 24px\)/)
    assert.match(layout, /var\(--mc-page-max-width, 1440px\)/)
  }

  assert.doesNotMatch(staffLayout, /(?:236|1480)px/)
  assert.doesNotMatch(adminLayout, /:width="260"/)
})

test('shared PageHeader typography and actions wrap without changing page rhythm', () => {
  assert.match(foundation, /\.mc-page-surface :is\([\s\S]*?\.arco-page-header-extra[\s\S]*?min-width:\s*0/)
  assert.match(foundation, /\.mc-page-surface \.arco-page-header-title\s*\{[\s\S]*?font-size:\s*var\(--mc-type-page-title-size\)/)
  assert.match(foundation, /\.mc-page-surface \.arco-page-header-subtitle\s*\{[\s\S]*?line-height:\s*var\(--mc-type-page-subtitle-line-height\)/)
  assert.match(foundation, /\.mc-page-surface \.arco-page-header-extra\s*\{[\s\S]*?white-space:\s*normal/)
  assert.match(foundation, /\.mc-page-surface \.arco-page-header-extra > \.arco-space\s*\{[\s\S]*?flex-wrap:\s*wrap/)
  assert.match(foundation, /@media \(max-width: 1099px\)[\s\S]*?\.arco-page-header-extra[\s\S]*?flex:\s*1 1 100%/)
})

test('page gutters step down through the shared responsive scale', () => {
  assert.match(foundation, /--mc-page-gutter:\s*24px/)
  assert.match(foundation, /@media \(max-width: 1279px\)[\s\S]*?--mc-page-gutter:\s*20px/)
  assert.match(foundation, /@media \(max-width: 767px\)[\s\S]*?--mc-page-gutter:\s*16px/)
  assert.match(foundation, /@media \(max-width: 479px\)[\s\S]*?--mc-page-gutter:\s*12px/)
})
