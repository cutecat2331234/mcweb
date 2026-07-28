import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

const root = process.cwd()

function source(path: string): string {
  return readFileSync(resolve(root, path), 'utf8')
}

test('public homepage copy describes user value instead of implementation details', () => {
  const en = source('app/javascript/locales/en.ts')
  const zhCN = source('app/javascript/locales/zh-CN.ts')
  const layout = source('app/javascript/layouts/WebsiteLayout.vue')

  for (const locale of [en, zhCN]) {
    assert.doesNotMatch(locale, /Players use \/app|玩家统一入口 \/app/)
    assert.doesNotMatch(locale, /stat3Value:\s*'Rails 8'/)
    assert.doesNotMatch(locale, /User features live under|用户功能位于/)
  }

  assert.match(en, /stat2Value:\s*'Player hub'/)
  assert.match(zhCN, /stat2Value:\s*'玩家中心'/)
  assert.doesNotMatch(layout, /\bappPrefix\b/)
})

test('member-facing copy avoids competitor and implementation labels', () => {
  const en = source('app/javascript/locales/en.ts')
  const zhCN = source('app/javascript/locales/zh-CN.ts')
  const search = source('app/javascript/pages/Community/Search/Index.vue')

  for (const locale of [en, zhCN]) {
    assert.doesNotMatch(locale, /Discourse|XenForo|WooCommerce/)
    assert.doesNotMatch(locale, /ruby tutorial/)
    assert.doesNotMatch(locale, /Unknown block: \{type\}|未知区块：\{type\}/)
  }

  assert.match(search, /forum\.search\.exampleQuery/)
  assert.doesNotMatch(search, /ruby tutorial/)
})
