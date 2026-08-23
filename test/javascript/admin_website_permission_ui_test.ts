import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

function source(relativePath: string) {
  return readFileSync(resolve(process.cwd(), relativePath), 'utf8')
}

const navigationPage = source('app/javascript/pages/Admin/Website/NavItems/Index.vue')
const themeForm = source('app/javascript/pages/Admin/Website/Themes/Form.vue')
const themeController = source('app/controllers/admin/website/themes_controller.rb')

test('website navigation hides mutation controls from read-only administrators', () => {
  assert.match(navigationPage, /canEdit: boolean/)
  assert.match(navigationPage, /<a-card\s+v-if="canEdit"/)
  assert.match(navigationPage, /\.\.\.\(props\.canEdit/)
  assert.match(navigationPage, /<template v-if="canEdit" #actions=/)
  assert.match(navigationPage, /if \(!props\.canEdit\) return/)
})

test('website navigation exposes its existing update endpoint through the Arco editor', () => {
  assert.match(navigationPage, /const editingId = ref<number \| null>\(null\)/)
  assert.match(navigationPage, /function startEditing\(item: NavItem\)/)
  assert.match(navigationPage, /router\.patch\(`\$\{props\.submitUrl\}\/\$\{editingId\.value\}`/)
  assert.match(navigationPage, /@click="startEditing\(record\)"/)
  assert.match(navigationPage, /@click="resetDraft"/)
  assert.match(navigationPage, /if \(requestSucceeded\(page\)\) resetDraft\(\)/)
  assert.match(navigationPage, /requestSucceeded\(page\) && editingId\.value === item\.id/)
})

test('persisted website themes expose the existing delete operation with shared confirmation', () => {
  assert.match(themeForm, /import \{ confirm \} from '@\/lib\/arcoConfirm'/)
  assert.match(themeForm, /deleteUrl\?: string \| null/)
  assert.match(themeForm, /variant: 'destructive'/)
  assert.match(themeForm, /form\.delete\(props\.deleteUrl\)/)
  assert.doesNotMatch(themeForm, /active: boolean/)
  assert.match(
    themeForm,
    /<a-button v-if="deleteUrl" html-type="button" status="danger" @click="destroy">/,
  )
  assert.doesNotMatch(themeController, /permit\([^\n]*:active/)
  assert.match(themeController, /::Website::Page\.with_lifecycle/)
})
