import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

const source = readFileSync(
  resolve(process.cwd(), 'app/javascript/pages/Admin/Forum/Attachments/Index.vue'),
  'utf8',
)

test('attachment security console uses Arco primitives with relaxed card and table borders', () => {
  assert.match(source, /from '@mcweb\/ui'/)
  assert.match(source, /<Grid :cols="\{ xs: 1, sm: 2, xl: 5 \}"/)
  assert.match(source, /<Descriptions/)
  assert.match(source, /<Table/)
  assert.match(source, /:bordered="false"/)
  assert.doesNotMatch(source, /bordered="\{ cell: true \}"/)
  assert.doesNotMatch(source, /<a-(?:card|table|select|pagination)/)
})

test('attachment lifecycle has separate desktop table and mobile cards', () => {
  assert.match(source, /class="hidden overflow-x-auto lg:block"/)
  assert.match(source, /class="space-y-3 lg:hidden"/)
  assert.match(source, /:scroll="\{ minWidth: 1340 \}"/)
  assert.match(source, /v-for="upload in uploads"/)
})

test('attachment page renders safe lifecycle fields without raw scanner errors', () => {
  assert.match(source, /scan_result_code/)
  assert.match(source, /scanResultLabel/)
  assert.match(source, /admin\.attachments\.scanResultCodes/)
  assert.match(source, /scan_attempts/)
  assert.match(source, /cleanup_attempts/)
  assert.doesNotMatch(source, /\{\{\s*(?:record|upload|releaseUpload\?)\.scan_result_code/)
  assert.doesNotMatch(source, /scan_error_message|cleanup_error_message/)
})

test('attachment retry actions use Arco confirmation and stay permission-driven by server URLs', () => {
  assert.match(source, /actions: \{[\s\S]*?retry_scan_url\?: string/)
  assert.match(source, /actions\.retry_cleanup_url/)
  assert.match(source, /await confirm\(/)
  assert.match(source, /router\.post\(upload\.actions\.retry_scan_url/)
  assert.match(source, /router\.post\(upload\.actions\.retry_cleanup_url/)
})

test('quarantine release keeps the review form open on JSON errors and reloads only queue props', () => {
  assert.match(source, /HttpError, postJson/)
  assert.match(source, /await postJson<\{ released\?: true; revoked\?: true \}>/)
  assert.match(source, /releaseError\.value = releaseErrorMessage\(error\)/)
  assert.match(source, /v-if="releaseError"/)
  assert.match(source, /router\.reload\(\{[\s\S]*only: \['uploads', 'pagination', 'filterCounts', 'summary', 'quotaUsage'\]/)
  assert.doesNotMatch(source, /router\.post\(\s*upload\.actions\.release_quarantine_url/)
})

test('manual release state is visible and revocation uses the same audited modal flow', () => {
  assert.match(source, /manual_review_status: 'none' \| 'released' \| 'revoked'/)
  assert.match(source, /actions\.revoke_release_url/)
  assert.match(source, /openRevokeReview/)
  assert.match(source, /expectedReviewConfirmation/)
  assert.match(source, /admin\.attachments\.revokeWarning/)
  assert.match(source, /reviewMode === 'release'/)
})
