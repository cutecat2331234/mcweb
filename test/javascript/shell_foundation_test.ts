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
const appStyle = readFileSync(
  resolve(process.cwd(), 'app/javascript/styles/applications/account.css'),
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

function relativeLuminance(hex: string) {
  const channels = hex.match(/[a-f\d]{2}/gi)?.map((value) => Number.parseInt(value, 16) / 255)
  assert.ok(channels && channels.length === 3, `expected six-digit hex color, received ${hex}`)
  const [red, green, blue] = channels.map((value) => (
    value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4
  ))
  return (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
}

function contrastRatio(foreground: string, background: string) {
  const lighter = Math.max(relativeLuminance(foreground), relativeLuminance(background))
  const darker = Math.min(relativeLuminance(foreground), relativeLuminance(background))
  return (lighter + 0.05) / (darker + 0.05)
}

test('admin and application style roots load one shared shell geometry contract', () => {
  assert.match(adminEntry, /@\/styles\/applications\/admin\.css/)
  assert.match(appStyle, /@import "\.\.\/shell-foundation\.css"/)

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

test('shared filled primary buttons retain readable labels in every interactive state', () => {
  const colors = {
    foreground: '#ffffff',
    resting: '#165dff',
    hover: '#0f4fe5',
    active: '#0e42d2',
  }

  for (const [state, color] of Object.entries(colors).filter(([name]) => name !== 'foreground')) {
    assert.ok(
      contrastRatio(colors.foreground, color) >= 4.5,
      `${state} primary button contrast must meet WCAG AA`,
    )
  }

  for (const [token, color] of [
    ['--mc-control-primary-foreground', colors.foreground],
    ['--mc-control-primary-background', colors.resting],
    ['--mc-control-primary-background-hover', colors.hover],
    ['--mc-control-primary-background-active', colors.active],
  ]) {
    assert.match(foundation, new RegExp(`${token}:\\s*${color}`, 'i'))
  }

  assert.match(
    foundation,
    /\.arco-btn\.arco-btn-primary:not\([\s\S]*?:is\(:hover, :focus-visible\)[\s\S]*?background:\s*var\(--mc-control-primary-background-hover\)/,
  )
  assert.match(
    foundation,
    /\.arco-btn\.arco-btn-primary:not\([\s\S]*?:active[\s\S]*?background:\s*var\(--mc-control-primary-background-active\)/,
  )
})

test('page gutters step down through the shared responsive scale', () => {
  assert.match(foundation, /--mc-page-gutter:\s*24px/)
  assert.match(foundation, /@media \(max-width: 1279px\)[\s\S]*?--mc-page-gutter:\s*20px/)
  assert.match(foundation, /@media \(max-width: 767px\)[\s\S]*?--mc-page-gutter:\s*16px/)
  assert.match(foundation, /@media \(max-width: 479px\)[\s\S]*?--mc-page-gutter:\s*12px/)
})

test('compound Arco detail views retain one token-backed content surface', () => {
  assert.match(
    foundation,
    /\.mc-page-surface \.arco-collapse-item-content,[\s\S]*?\.arco-descriptions-border,[\s\S]*?\.arco-descriptions-item-value-block,[\s\S]*?\.arco-table-container,[\s\S]*?\.arco-table-body[\s\S]*?background-color:\s*var\(--color-bg-2\)/,
  )
  assert.doesNotMatch(foundation, /\.arco-collapse-item-content[\s\S]{0,500}(?:#[0-9a-f]{3,8}|rgba?\()/i)
})
