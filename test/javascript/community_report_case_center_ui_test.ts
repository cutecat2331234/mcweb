import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

import en from '../../app/javascript/locales/en.ts'
import zhCN from '../../app/javascript/locales/zh-CN.ts'

function source(path: string) {
  return readFileSync(resolve(process.cwd(), path), 'utf8')
}

const pages = [
  source('app/javascript/pages/Community/Reports/New.vue'),
  source('app/javascript/pages/Community/Reports/Index.vue'),
  source('app/javascript/pages/Community/Reports/Show.vue'),
]
const indexPage = pages[1]
const showPage = pages[2]
const controller = source('app/controllers/community/reports_controller.rb')
const serializer = source('app/services/community/reporter_report_serializer.rb')

test('reporter case center uses only shared UI primitives and no custom visual styling', () => {
  for (const page of pages) {
    assert.match(page, /from '@mcweb\/ui'/)
    assert.match(page, /defineOptions\(\{ layout: PortalLayout \}\)/)
    assert.doesNotMatch(
      page,
      /<style\b|\s(?:class|:class|v-bind:class|style|:style|v-bind:style)=|<button\b|<form\b|<input\b|<textarea\b/,
    )
    assert.doesNotMatch(page, /gradient|translate[XY]?\(|translate-[xy]?-|transition-transform|hover:-?translate/)
  }
})

test('pending mutations carry explicit desired state version and bounded idempotency keys', () => {
  assert.match(showPage, /createIdempotencyKey/)
  assert.match(showPage, /desired_state: 'withdrawn'/)
  assert.match(showPage, /lock_version: props\.report\.lock_version/)
  assert.match(showPage, /from '@\/lib\/arcoConfirm'/)
  assert.match(showPage, /responseHasFormErrors\(page\)/)
  assert.match(showPage, /submittedSupplement/)
  assert.match(showPage, /:disabled="supplementForm\.processing"/)
  assert.doesNotMatch(showPage, /toggle/i)
})

test('reporter endpoints are owner scoped private and history encrypted', () => {
  assert.match(controller, /where\(reporter_id: current_user\.id\)\.find\(params\[:id\]\)/)
  assert.match(controller, /Cache-Control", "private, no-store"/)
  assert.match(controller, /X-Robots-Tag", "noindex, nofollow"/)
  assert.equal((controller.match(/encrypt_history: true/g) ?? []).length, 4)
  assert.match(indexPage, /<meta name="robots" content="noindex,nofollow">/)
  assert.match(showPage, /<meta name="robots" content="noindex,nofollow">/)
})

test('reporter serializer has an explicit safe target and field contract', () => {
  assert.match(serializer, /SAFE_TARGET_KINDS/)
  assert.doesNotMatch(serializer, /\.reportable\b|review_note|reviewer|assignee|evidence|penalty|duration|member_status/)
  assert.doesNotMatch(indexPage + showPage, /review_note|reviewer|assignee|evidence|penalty|duration|member_status/)
})

test('report case center copy is symmetric in English and Simplified Chinese', () => {
  assert.deepEqual(
    Object.keys(en.forum.reports).sort(),
    Object.keys(zhCN.forum.reports).sort(),
  )
  assert.deepEqual(
    Object.keys(en.forum.reports.status).sort(),
    Object.keys(zhCN.forum.reports.status).sort(),
  )
  assert.deepEqual(
    Object.keys(en.forum.reports.outcome).sort(),
    Object.keys(zhCN.forum.reports.outcome).sort(),
  )
})
