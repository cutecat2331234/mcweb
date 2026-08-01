import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import test from 'node:test'

const indexSource = fs.readFileSync(
  path.join(process.cwd(), 'app/javascript/pages/Admin/Store/Fulfillments/Index.vue'),
  'utf8',
)
const showSource = fs.readFileSync(
  path.join(process.cwd(), 'app/javascript/pages/Admin/Store/Fulfillments/Show.vue'),
  'utf8',
)

test('fulfillment recovery uses Arco queue, summaries, and a bounded timeline', () => {
  for (const component of ['PageHeader', 'Statistic', 'Table', 'Tag', 'Alert']) {
    assert.match(indexSource, new RegExp(`<${component}`))
  }
  assert.match(showSource, /<a-descriptions/)
  assert.match(showSource, /<a-timeline/)
  assert.match(showSource, /<HighRiskActionModal/)
  assert.doesNotMatch(
    indexSource,
    /\s(?:class|:class|v-bind:class|style|:style|v-bind:style)=|<style\b|<(?:form|label|input|select|textarea)(?:\s|>)/,
  )
  assert.doesNotMatch(indexSource + showSource, /window\.location|location\.reload/)
})

test('signed retry and cancel refresh only fulfillment detail props', () => {
  assert.match(showSource, /authorization-url="paths\.authorize"/)
  assert.match(showSource, /action-url="paths\.execute"/)
  assert.match(showSource, /action = 'retry'/)
  assert.match(showSource, /action = 'cancel'/)
  assert.match(showSource, /router\.reload\(\{/)
  assert.match(showSource, /only: \['fulfillment', 'attempts', 'permissions'\]/)
})
