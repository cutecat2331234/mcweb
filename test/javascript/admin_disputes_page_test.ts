import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import test from 'node:test'

const source = fs.readFileSync(
  path.join(process.cwd(), 'app/javascript/pages/Admin/Store/Disputes/Index.vue'),
  'utf8',
)

test('dispute workbench uses Arco hierarchy, filters, Drawer, Timeline, and deadline progress', () => {
  for (const component of [
    'PageHeader',
    'Alert',
    'Statistic',
    'Table',
    'Tag',
    'Drawer',
    'Descriptions',
    'Timeline',
    'Progress',
    'HighRiskActionModal',
  ]) {
    assert.match(source, new RegExp(`<${component}`))
  }

  for (const filter of ['filters.status', 'filters.provider', 'filters.risk', 'filters.assignee', 'filters.due']) {
    assert.match(source, new RegExp(filter.replace('.', '\\.')))
  }
  assert.match(source, /:cols="\{ xs: 1, sm: 2, lg: 5 \}"/)
  assert.match(source, /:span="\{ xs: 24, sm: 12, xl: 4 \}"/)
  assert.doesNotMatch(
    source,
    /\s(?:class|:class|v-bind:class|style|:style|v-bind:style)=|<style\b|<(?:form|label|input|select|textarea)(?:\s|>)/,
  )
  assert.doesNotMatch(source, /window\.location|location\.reload/)
})

test('dispute actions remain local, idempotent, and permission-shaped', () => {
  assert.match(source, /createIdempotencyKey\(\)/)
  assert.match(source, /expected_lock_version/)
  assert.match(source, /permissions\.sensitiveRead/)
  assert.match(source, /permissions\.acceptLoss/)
  assert.match(source, /permissions\.rightsManage/)
  assert.match(source, /router\.reload\(\{ only: \['summary', 'rows'\] \}\)/)
  assert.match(source, /downloadTokenUrl/)
})
