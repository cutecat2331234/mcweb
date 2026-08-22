import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const read = (path: string) => readFileSync(path, 'utf8')

const index = read('app/javascript/pages/Admin/Roles/Index.vue')
const show = read('app/javascript/pages/Admin/Roles/Show.vue')
const form = read('app/javascript/pages/Admin/Roles/Form.vue')
const controller = read('app/controllers/admin/roles_controller.rb')
const english = read('app/javascript/locales/en.ts')
const chinese = read('app/javascript/locales/zh-CN.ts')

test('role administration uses dedicated responsive Arco pages', () => {
  assert.match(controller, /Admin\/Roles\/Index/)
  assert.match(controller, /Admin\/Roles\/Show/)
  assert.match(controller, /Admin\/Roles\/Form/)
  assert.match(index, /<a-table/)
  assert.match(index, /:span="\{ xs: 24, sm: 12, md: 0 \}"/)
  assert.match(index, /:span="\{ xs: 0, md: 24 \}"/)
  assert.match(show, /<a-descriptions/)
  assert.match(show, /<a-list/)
})

test('role editor keeps stable identifiers and requires safe retirement', () => {
  assert.match(form, /:disabled="!canManage \|\| role\.id !== null"/)
  assert.match(form, /role\.memberCount > 0/)
  assert.match(form, /replacement_role_id/)
  assert.match(form, /replacementRoles\.length === 0/)
  assert.match(form, /retirementForm\.delete/)
  assert.match(form, /permissionRemovalOnly/)
})

test('role pages add no private visual language and keep bilingual copy', () => {
  for (const source of [ index, show, form ]) {
    assert.doesNotMatch(source, /<style(?:\s|>)/)
    assert.doesNotMatch(source, /gradient|translate[XY]?\(|hoverable/i)
  }

  for (const locale of [ english, chinese ]) {
    assert.match(locale, /roles:\s*\{/)
    assert.match(locale, /replacementRequired:/)
    assert.match(locale, /permissionRemovalOnly:/)
  }
})
