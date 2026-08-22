import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

const page = readFileSync(
  resolve(process.cwd(), 'app/javascript/pages/Admin/Forum/ModerationWorkbench/Index.vue'),
  'utf8',
)
const modal = readFileSync(
  resolve(process.cwd(), 'app/javascript/components/admin/ModerationActionModal.vue'),
  'utf8',
)

test('moderation workbench uses Arco with all contracted filters and SPA pagination', () => {
  assert.match(page, /from '@mcweb\/ui'/)
  assert.match(page, /import AdminLayout from '@\/layouts\/AdminLayout\.vue'/)
  for (const filter of [
    'source_kind',
    'status',
    'priority',
    'section_id',
    'assignee_id',
    'from',
    'to',
    'risk_level',
  ]) {
    assert.match(page, new RegExp(`field="${filter}"`))
  }
  assert.match(page, /<DatePicker[\s\S]*?value-format="YYYY-MM-DD"/)
  assert.match(page, /<Pagination/)
  assert.match(page, /router\.get\('\/admin\/forum\/moderation-workbench'/)
  assert.doesNotMatch(page, /(?:document|window)\.location\.reload/)
})

test('desktop table and mobile cards both provide selection and moderation access', () => {
  assert.match(page, /window\.matchMedia\('\(max-width: 767px\)'\)/)
  assert.match(page, /v-else-if="!isMobile"/)
  assert.match(page, /<Space v-else direction="vertical"/)
  assert.match(page, /v-model:selected-keys="selectedCaseIds"/)
  assert.match(page, /:row-selection="rowSelection"/)
  assert.match(page, /<Checkbox/)
  assert.match(page, /commonActions/)
  assert.match(page, /available_actions/)
  assert.doesNotMatch(page, /\s(?:v-bind:class|:class|class)=/)
  assert.doesNotMatch(page, /<style\b/)
})

test('drawer loads detail separately and handles evidence truncation, claiming, assigning, and notes', () => {
  assert.match(page, /<Drawer/)
  assert.match(page, /getJson<\{ case: ModerationCaseDetail \}>/)
  assert.match(page, /`\/admin\/forum\/moderation-workbench\/\$\{id\}`/)
  assert.match(page, /evidenceWasTruncated/)
  assert.match(page, /details\.evidenceTruncated/)
  assert.match(page, /:auto-size="\{ minRows: 2, maxRows: 12 \}"/)
  assert.match(page, /\/claim`/)
  assert.match(page, /\{ lock_version: item\.lock_version \}/)
  assert.match(page, /\/assign`/)
  assert.match(page, /assigneeId\.value === '' \|\| assigneeId\.value == null/)
  assert.match(page, /v-model="assigneeId"[\s\S]*?allow-clear/)
  assert.match(page, /actions\.unassign/)
  assert.match(page, /\/notes`/)
  assert.match(page, /body: noteBody\.value\.trim\(\)/)
  assert.match(page, /capabilities\.can_assign/)
  assert.match(page, /capabilities\.can_note/)
})

test('action modal implements authorization preview and typed-confirmed execution', () => {
  assert.match(modal, /\/authorize-action/)
  assert.match(modal, /\/execute-action/)
  assert.match(modal, /action: props\.action/)
  assert.match(modal, /case_ids: props\.caseIds/)
  assert.match(modal, /reason: reason\.value\.trim\(\)/)
  assert.match(modal, /attributes: actionAttributes\.value/)
  assert.match(modal, /request_id: requestId\.value/)
  assert.match(modal, /authorization_token: challenge\.authorization_token/)
  assert.match(modal, /typed_confirmation: typedConfirmation\.value/)
  assert.match(modal, /typedConfirmation\.value === authorization\.value\?\.typed_confirmation/)
  assert.match(modal, /warningPoints/)
  assert.match(modal, /warningExpireDays/)
  assert.match(modal, /durationDays/)
  assert.match(modal, /action === 'ban_user' \? 0 : 1/)
  assert.match(modal, /if \(!props\.visible \|\| !props\.action\) return ''/)
  assert.match(modal, /:title="modalTitle"/)
  assert.doesNotMatch(modal, /actions\.\$\{action\}/)
})

test('preview and per-item execution results stay inside the modal until explicitly closed', () => {
  assert.match(modal, /authorization\.preview/)
  assert.match(modal, /execution\.results/)
  assert.match(modal, /row-key="case_id"/)
  assert.match(modal, /execution\.replayed/)
  assert.match(modal, /emit\('completed', execution\.value\)/)
  assert.doesNotMatch(modal, /emit\('update:visible', false\)[\s\S]{0,120}emit\('completed'/)
  assert.doesNotMatch(modal, /router\.reload|location\.reload/)
  assert.match(page, /watch\(bulkVisible/)
  assert.match(page, /router\.reload\(\{[\s\S]*only: \['cases', 'pagination'\]/)
})

test('new workbench copy is namespaced through i18n keys', () => {
  assert.match(page, /admin\.moderationWorkbench\./)
  assert.match(modal, /admin\.moderationWorkbench\./)
  assert.doesNotMatch(page, />\s*(?:领取|转派|备注|筛选|取消|确认)\s*</)
  assert.doesNotMatch(modal, />\s*(?:预览|执行|取消|确认|完成)\s*</)
})
