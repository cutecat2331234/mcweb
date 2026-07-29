import assert from 'node:assert/strict'
import test from 'node:test'
import {
  applyBaseline,
  applyAllowlist,
  looksLikeTechnicalIdentifier,
  parseScanDirectories,
  scanRubySource,
  scanVueSource,
  validateAllowlist,
  validateBaseline,
} from '../../scripts/check-user-facing-copy.mjs'

test('extension copy scans accept only explicit relative directories', () => {
  assert.deepEqual(parseScanDirectories([
    '--scan-directory=ee/app/javascript',
    '--scan-directory=ee\\app\\controllers',
    '--scan-directory=ee/app/javascript',
    '--write-baseline',
  ]), [
    'ee/app/javascript',
    'ee/app/controllers',
  ])

  for (const directory of [
    '',
    '../private',
    'ee/../../private',
    '/absolute',
    'C:\\absolute',
    'ee/app/javascript;whoami',
  ]) {
    assert.throws(
      () => parseScanDirectories([`--scan-directory=${directory}`]),
      /unsafe scan directory/,
    )
  }
})

test('Vue scanner finds literal text and user-facing attributes', () => {
  const findings = scanVueSource(`
    <template>
      <a-card title="Account settings">
        保存修改
        <a-input placeholder="Email address" />
      </a-card>
    </template>
  `, 'app/javascript/pages/Example.vue')

  assert.deepEqual(
    findings.map(({ kind, text }) => ({ kind, text })),
    [
      { kind: 'vue-text', text: '保存修改' },
      { kind: 'vue-attribute:title', text: 'Account settings' },
      { kind: 'vue-attribute:placeholder', text: 'Email address' },
    ],
  )
})

test('Vue scanner ignores bindings, translations, code, and technical identifiers', () => {
  const findings = scanVueSource(`
    <template>
      <a-card :title="t('admin.users.title')" aria-label="API">
        {{ t('common.save') }}
        <code>system.jobs.read</code>
        <a-tag>ID</a-tag>
      </a-card>
    </template>
  `)

  assert.deepEqual(findings, [])
})

test('Ruby scanner limits itself to copy-bearing call sites', () => {
  const source = `
    ServiceResult.failure(error: "The order cannot be refunded")
    errors.add(:email, "is already registered")
    redirect_to root_path, notice: I18n.t("mcweb.flash.saved")
    payload = { error: "invalid_state", title: "system.jobs.read" }
    endpoint = "https://example.test/api"
  `
  const findings = scanRubySource(source)

  assert.deepEqual(
    findings.map(({ kind, text }) => ({ kind, text })),
    [
      { kind: 'ruby-user-keyword', text: 'The order cannot be refunded' },
      { kind: 'ruby-validation', text: 'is already registered' },
    ],
  )
})

test('technical identifier classifier does not confuse IDs with copy', () => {
  for (const value of [
    'system.jobs.read',
    'forum_post-created',
    'POST /api/v1/orders',
    'application/json',
    'https://mcweb.test/app',
    '550e8400-e29b-41d4-a716-446655440000',
    'API',
    'Redis',
  ]) {
    assert.equal(looksLikeTechnicalIdentifier(value), true, value)
  }
  assert.equal(looksLikeTechnicalIdentifier('Save changes'), false)
  assert.equal(looksLikeTechnicalIdentifier('保存修改'), false)
})

test('exact reviewed allowlist entries suppress findings and stale entries fail closed', () => {
  const findings = scanVueSource(
    '<template><p>Brand promise</p><p>Needs translation</p></template>',
    'app/javascript/pages/Brand.vue',
  )
  const document = {
    version: 1,
    entries: [{
      file: 'app/javascript/pages/Brand.vue',
      kind: 'vue-text',
      text: 'Brand promise',
      reason: 'Legally approved product trademark sentence',
    }],
  }
  const result = applyAllowlist(findings, document)

  assert.deepEqual(result.violations.map((entry) => entry.text), ['Needs translation'])
  assert.deepEqual(result.stale, [])

  const stale = applyAllowlist([], document)
  assert.equal(stale.stale.length, 1)
})

test('allowlist requires concrete reasons and rejects duplicates', () => {
  assert.throws(
    () => validateAllowlist({
      version: 1,
      entries: [{ file: 'a.vue', kind: 'vue-text', text: 'Brand', reason: 'short' }],
    }),
    /at least 8 characters/,
  )

  const entry = {
    file: 'a.vue',
    kind: 'vue-text',
    text: 'Brand',
    reason: 'Reviewed trademark copy',
  }
  assert.throws(
    () => validateAllowlist({ version: 1, entries: [entry, entry] }),
    /duplicate/,
  )
})

test('baseline prevents new debt and rejects stale or duplicate inventory', () => {
  const findings = scanVueSource(
    '<template><p>Known debt</p><p>New debt</p></template>',
    'app/javascript/pages/Debt.vue',
  )
  const known = {
    file: 'app/javascript/pages/Debt.vue',
    kind: 'vue-text',
    text: 'Known debt',
    category: 'historical-compatibility',
    reason: 'Legacy client contract pending removal',
    trackingIssue: 'MCWEB-123',
    reviewBy: '2099-12-31',
  }
  const result = applyBaseline(findings, { version: 2, entries: [known] })

  assert.deepEqual(result.violations.map((entry) => entry.text), ['New debt'])
  assert.deepEqual(result.stale, [])
  assert.equal(applyBaseline([], { version: 2, entries: [known] }).stale.length, 1)
  assert.throws(
    () => validateBaseline({ version: 2, entries: [known, known] }),
    /duplicate/,
  )
})

test('baseline categories are constrained and compatibility debt expires', () => {
  const base = {
    file: 'app/javascript/pages/Admin/Demo.vue',
    kind: 'vue-text',
    text: 'Demo copy',
    reason: 'Developer-only compatibility fixture',
  }

  assert.doesNotThrow(() => validateBaseline({
    version: 2,
    entries: [{ ...base, category: 'development-demo' }],
  }))
  assert.throws(
    () => validateBaseline({
      version: 2,
      entries: [{ ...base, category: 'unreviewed' }],
    }),
    /unsupported category/,
  )
  assert.throws(
    () => validateBaseline({
      version: 2,
      entries: [{
        ...base,
        category: 'historical-compatibility',
        trackingIssue: 'MCWEB-123',
        reviewBy: '2020-01-01',
      }],
    }),
    /has expired/,
  )
})
