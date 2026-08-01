import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

function projectSource(path: string): string {
  return readFileSync(resolve(process.cwd(), path), 'utf8')
}

test('admin dashboard presents translated audit actions without hiding their codes', () => {
  const dashboard = projectSource(
    'app/javascript/pages/Admin/Dashboard/Index.vue',
  )
  const controller = projectSource(
    'app/controllers/admin/dashboard_controller.rb',
  )

  assert.match(dashboard, /actionLabel: string/)
  assert.match(dashboard, /actionCode: string/)
  assert.match(dashboard, /\{\{ record\.actionLabel \}\}/)
  assert.match(
    dashboard,
    /type="secondary"[\s\S]*?code[\s\S]*?\{\{ record\.actionCode \}\}/,
  )
  assert.doesNotMatch(dashboard, /v-html/)
  assert.match(
    controller,
    /actionLabel: Administration::AuditActionLabel\.call\(log\.action\)/,
  )
  assert.match(controller, /actionCode: log\.action/)
})
