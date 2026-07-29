import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import test from 'node:test'

const source = fs.readFileSync(
  path.join(process.cwd(), 'app/controllers/admin/users_controller.rb'),
  'utf8',
)

test('admin users controller does not ship hardcoded Han copy or raw enum labels', () => {
  assert.doesNotMatch(source, /\p{Script=Han}/u)
  assert.match(source, /mcweb\.admin\.users\.statuses/)
  assert.match(source, /mcweb\.admin\.users\.account_types/)
})
