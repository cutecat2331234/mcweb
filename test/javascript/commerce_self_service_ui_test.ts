import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

const productPage = readFileSync(
  resolve(process.cwd(), 'app/javascript/pages/Commerce/Products/Show.vue'),
  'utf8',
)
const orderPage = readFileSync(
  resolve(process.cwd(), 'app/javascript/pages/Commerce/Orders/Show.vue'),
  'utf8',
)

test('commerce self-service actions use the established component library', () => {
  for (const page of [productPage, orderPage]) {
    assert.match(page, /components\/ui\/Button\.vue/)
    assert.match(page, /components\/ui\/Textarea\.vue/)
  }

  assert.match(productPage, /components\/ui\/FileInput\.vue/)
  assert.match(productPage, /reviewForm\.patch\(props\.updateReviewUrl/)
  assert.match(productPage, /retained_photo_ids/)
  assert.match(productPage, /forumSnapshotNotice/)
})

test('questions answers and pending refunds expose edit or withdrawal affordances', () => {
  assert.match(productPage, /question:\s*\{[\s\S]*?expected_version: editingQuestionVersion\.value/)
  assert.match(productPage, /answer:\s*\{[\s\S]*?expected_version: editingAnswerVersion\.value/)
  assert.match(productPage, /photo_selection_present = true/)
  assert.match(productPage, /expected_version = props\.userReview\.lock_version/)
  assert.match(productPage, /if \(responseHasAlert\(page\)\) return/)
  assert.match(productPage, /deleteQuestion\(q\.deleteUrl\)/)
  assert.match(productPage, /deleteAnswer\(answer\.delete_url\)/)
  assert.match(orderPage, /refund\.can_withdraw && refund\.withdraw_url/)
  assert.match(orderPage, /router\.delete\(refund\.withdraw_url/)
})
