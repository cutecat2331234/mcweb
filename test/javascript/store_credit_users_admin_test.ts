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
  const ledgerStart = show.indexOf('v-if="props.storeCreditLedger"')
  const ledgerEnd = show.indexOf('v-if="props.accountForm && canEditAccountAccess"', ledgerStart)

  assert.ok(ledgerStart >= 0, 'store-credit ledger section must remain present')
  assert.ok(ledgerEnd > ledgerStart, 'store-credit ledger section must remain independently bounded')
  const ledger = show.slice(ledgerStart, ledgerEnd)

  assert.match(show, /storeCreditLedger\?: StoreCreditLedger/)
  assert.match(ledger, /<a-table[\s\S]*props\.storeCreditLedger\.transactions/)
  assert.match(ledger, /row-key="ledger_id"/)
  assert.match(ledger, /balance_before_label && record\.balance_after_label/)
  assert.match(ledger, /storeCreditOlderTransactions/)
  assert.match(ledger, /router\.visit\(props\.storeCreditLedger\.pagination\.next_url/)
  assert.doesNotMatch(ledger, /window\.location\.(?:assign|replace|reload)/)
})

test('member wallet uses one approved UI-library table with order and cursor navigation', () => {
  const wallet = source('app/javascript/pages/Commerce/Wallet/Show.vue')
  const usesSharedTable = /components\/ui\/Table\.vue/.test(wallet)
  const usesArcoTable = /<a-table\b/.test(wallet)

  assert.equal(
    Number(usesSharedTable) + Number(usesArcoTable),
    1,
    'wallet must use exactly one approved table implementation',
  )
  assert.doesNotMatch(wallet, /<(?:table|thead|tbody|tr|th|td)\b/)
  assert.match(wallet, /balance_before_label && tx\.balance_after_label/)
  assert.match(wallet, /pagination\.has_more && pagination\.next_url/)

  if (usesSharedTable) {
    assert.match(wallet, /components\/ui\/Button\.vue/)
    assert.match(wallet, /v-for="tx in transactions" :key="tx\.ledger_id"/)
    assert.match(wallet, /<Link :href="routes\.storeOrders"/)
    assert.match(wallet, /<Link v-if="tx\.order_url" :href="tx\.order_url"/)
    assert.match(wallet, /<Link :href="pagination\.next_url" preserve-scroll>/)
    assert.doesNotMatch(wallet, /<a-table\b/)
  } else {
    assert.doesNotMatch(wallet, /@\/components\/ui\//)
    assert.match(wallet, /<a-table[\s\S]*:data="transactions"/)
    assert.match(wallet, /row-key="ledger_id"/)
    assert.match(wallet, /:href="routes\.storeOrders"[\s\S]*visitCommerceLink\(\$event, routes\.storeOrders\)/)
    assert.match(wallet, /<a-link[\s\S]*v-if="tx\.order_url"[\s\S]*:href="tx\.order_url"/)
    assert.match(wallet, /visitCommerceLink\(\$event, tx\.order_url\)/)
    assert.match(wallet, /function visitCommerceLink[\s\S]*event\.preventDefault\(\)[\s\S]*router\.visit\(href\)/)
    assert.match(wallet, /router\.visit\(pagination\.next_url, \{ preserveScroll: true \}\)/)
    assert.doesNotMatch(wallet, /<Table\b/)
  }
})
