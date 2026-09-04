import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

import en from '../../app/javascript/locales/en.ts'
import zhCN from '../../app/javascript/locales/zh-CN.ts'

function source(path: string) {
  return readFileSync(resolve(process.cwd(), path), 'utf8')
}

const userPages = [
  source('app/javascript/pages/Community/ReportAppeals/Index.vue'),
  source('app/javascript/pages/Community/ReportAppeals/Show.vue'),
]
const reviewComponents = [
  source('app/javascript/components/community/ReportAppealReviewIndex.vue'),
  source('app/javascript/components/community/ReportAppealReviewShow.vue'),
]
const uploadAdapter = source('app/javascript/components/community/SecureEvidenceUpload.vue')
const upload = source('app/javascript/components/secure-evidence/SecureEvidenceUpload.vue')

test('appeal surfaces use the shared Arco library without divergent motion or visual overrides', () => {
  for (const page of [...userPages, ...reviewComponents, upload]) {
    assert.match(page, /from '@mcweb\/ui'/)
    assert.doesNotMatch(page, /<style\b|gradient|translate[XY]?\(|transition-transform|hover:-?translate/)
    assert.doesNotMatch(page, /(?:class|:class|style|:style)=/)
  }
  assert.match(upload, /type="file"/)
  assert.match(upload, /hidden/)
  assert.match(upload, /<Button/)
  assert.match(uploadAdapter, /SharedSecureEvidenceUpload/)
  assert.doesNotMatch(uploadAdapter, /<style\b|(?:class|:class|style|:style)=/)
})

test('private draft submission exposes explicit upload cancel and versioned submit actions', () => {
  const show = userPages[1]
  assert.match(show, /appeal\.can_submit/)
  assert.match(show, /attachment_public_ids/)
  assert.match(show, /lock_version: props\.appeal\.lock_version/)
  assert.match(show, /createIdempotencyKey/)
  assert.match(show, /cancelAppeal/)
  assert.match(show, /discardAttachment/)
  assert.match(show, /\['uploading', 'pending', 'available', 'quarantined'\]/)
})

test('review UI keeps protected context separate and states that reversal is not automatic', () => {
  const show = reviewComponents[1]
  assert.match(show, /review\.publicCase/)
  assert.match(show, /review\.internalCase/)
  assert.match(show, /review\.noAutomaticReversal/)
  assert.match(show, /appeal\.can_decide/)
  assert.match(show, /SecureEvidenceUpload/)
  assert.match(show, /forum\.reportAppeals\.evidence\.state/)
  assert.match(show, /\['uploading', 'pending', 'available', 'quarantined'\]/)
})

test('appeal copy and nested vocabularies are symmetric in both locales', () => {
  assert.deepEqual(Object.keys(en.forum.reportAppeals).sort(), Object.keys(zhCN.forum.reportAppeals).sort())
  assert.deepEqual(
    Object.keys(en.forum.reportAppeals.status).sort(),
    Object.keys(zhCN.forum.reportAppeals.status).sort(),
  )
  assert.deepEqual(
    Object.keys(en.forum.reportAppeals.evidence).sort(),
    Object.keys(zhCN.forum.reportAppeals.evidence).sort(),
  )
})
