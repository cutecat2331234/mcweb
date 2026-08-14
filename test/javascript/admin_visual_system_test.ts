import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

const css = readFileSync(
  resolve(process.cwd(), 'app/javascript/styles/arco-admin.css'),
  'utf8',
)
const layout = readFileSync(
  resolve(process.cwd(), 'app/views/layouts/inertia_admin.html.erb'),
  'utf8',
)
const shell = readFileSync(
  resolve(process.cwd(), 'app/javascript/layouts/ArcoAdminLayout.vue'),
  'utf8',
)
const jobs = readFileSync(
  resolve(process.cwd(), 'app/javascript/pages/Admin/System/Jobs/Index.vue'),
  'utf8',
)

function ruleBody(source: string, selector: RegExp) {
  const match = source.match(selector)
  assert.ok(match, `missing CSS rule: ${selector}`)
  return match[1]
}

test('admin visual tokens live on the body so teleported Arco overlays inherit them', () => {
  assert.match(layout, /<body class="mcweb-admin antialiased">/)
  assert.match(css, /body\.mcweb-admin\s*\{[\s\S]*?--mc-admin-canvas:/)
  assert.match(css, /html\.dark body\.mcweb-admin\s*\{/)
  assert.match(css, /\.mcweb-admin \.arco-btn,/)
  assert.match(css, /\.mcweb-admin :is\([\s\S]*?\):focus-within/)
  assert.match(css, /\.arco-modal,\s*\.arco-drawer\s*\{[\s\S]*?var\(--mc-admin-shadow-md/)
})

test('admin geometry mixes crisp data surfaces with softer content and round semantic chips', () => {
  assert.match(css, /--mc-admin-radius-shell:\s*4px/)
  assert.match(css, /--mc-admin-radius-control:\s*7px/)
  assert.match(css, /--mc-admin-radius-card:\s*11px/)
  assert.match(css, /\.arco-table-container\s*\{[\s\S]*?var\(--mc-admin-radius-shell\)/)
  assert.match(css, /\.mcweb-admin \.arco-tag,[\s\S]*?border-radius:\s*999px/)
})

test('admin PageHeader supporting copy keeps its accessible semantic text color', () => {
  const sharedSubtitle = ruleBody(
    css,
    /\.arco-admin-main \.arco-page-header-subtitle\s*\{([^}]*)\}/,
  )
  const responsiveSubtitle = ruleBody(
    shell,
    /\.arco-admin-main :deep\(\.arco-page-header-subtitle\)\s*\{([^}]*)\}/,
  )

  assert.match(sharedSubtitle, /color:\s*var\(--color-text-2\)/)
  assert.doesNotMatch(sharedSubtitle, /--color-text-3/)
  assert.doesNotMatch(responsiveSubtitle, /\bcolor\s*:/)
})

test('medium-width page headers retain a padded surface instead of collapsing into loose text', () => {
  assert.match(shell, /@media \(max-width: 1099px\)[\s\S]*?\.arco-admin-main :deep\(\.arco-page-header\)\s*\{[\s\S]*?padding:\s*var\(--mc-page-header-padding, 14px\) !important/)
  assert.doesNotMatch(shell, /padding:\s*8px 0/)
})

test('admin task cards use a bounded Arco grid instead of a fixed four-column breakpoint', () => {
  assert.match(jobs, /<a-grid[\s\S]*?:cols="\{\s*xs:\s*1,\s*md:\s*2\s*\}"/)
  assert.match(jobs, /<a-grid-item v-for="task in manualTasks"/)
  assert.doesNotMatch(jobs, /:cols="\{\s*xs:\s*1,\s*md:\s*2,\s*xl:\s*4\s*\}"/)
  assert.doesNotMatch(jobs, /\s(?:class|:class|style|:style)=/)
  assert.doesNotMatch(jobs, /<(?:section|div|p|span)\b/)
  assert.doesNotMatch(css, /mc-admin-responsive-card-grid/)
})
