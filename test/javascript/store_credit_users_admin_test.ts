import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

function source(relativePath: string) {
  return readFileSync(new URL(`../../${relativePath}`, import.meta.url), 'utf8')
}

test('store-credit users have a store-scoped permission-gated Arco navigation entry', () => {
  const layout = source('app/javascript/layouts/ArcoAdminLayout.vue')
  const routes = source('app/javascript/lib/adminRoutes.ts')

  assert.match(routes, /storeCreditUsers: '\/admin\/store\/store-credits'/)
  assert.match(
    layout,
    /label: t\('admin\.storeCreditUsers'\),\s+href: adminRoutes\.storeCreditUsers,\s+permissionKey: 'store\.credit\.read'/,
  )
  assert.match(layout, /key: 'store',[\s\S]*moduleKey: 'store'/)
})

test('generic credit directory search uses Arco and Inertia without a document reload', () => {
  const index = source('app/javascript/pages/Admin/Generic/Index.vue')

  assert.match(index, /search\?: SearchFilterProps \| null/)
  assert.match(index, /<a-space[\s\S]*v-if="search"[\s\S]*role="search"/)
  assert.match(index, /<a-input-search/)
  assert.match(index, /@search="applySearch"/)
  assert.match(index, /router\.get\(\s*props\.search\.action/)
  assert.doesNotMatch(index, /window\.location\.(?:assign|replace|reload)/)
})

test('store-credit navigation copy is available in English and Chinese', () => {
  const english = source('app/javascript/locales/en.ts')
  const chinese = source('app/javascript/locales/zh-CN.ts')

  assert.match(english, /storeCreditUsers: 'Store credit accounts'/)
  assert.match(chinese, /storeCreditUsers: '余额用户'/)
})

test('store-credit detail renders the complete ledger with Arco components and cursor navigation', () => {
  const show = source('app/javascript/pages/Admin/Generic/Show.vue')

  assert.match(show, /storeCreditLedger\?: StoreCreditLedger/)
  assert.match(show, /<a-table[\s\S]*props\.storeCreditLedger\.transactions/)
  assert.match(show, /row-key="ledger_id"/)
  assert.match(show, /balance_before_label && record\.balance_after_label/)
  assert.match(show, /storeCreditOlderTransactions/)
  assert.match(show, /router\.visit\(props\.storeCreditLedger\.pagination\.next_url/)
  assert.doesNotMatch(show, /window\.location\.(?:assign|replace|reload)/)
})

test('member wallet uses the shared UI table and exposes older ledger pages', () => {
  const wallet = source('app/javascript/pages/Commerce/Wallet/Show.vue')

  assert.match(wallet, /components\/ui\/Table\.vue/)
  assert.match(wallet, /components\/ui\/Button\.vue/)
  assert.match(wallet, /v-for="tx in transactions" :key="tx\.ledger_id"/)
  assert.match(wallet, /balance_before_label && tx\.balance_after_label/)
  assert.match(wallet, /pagination\.has_more && pagination\.next_url/)
})
