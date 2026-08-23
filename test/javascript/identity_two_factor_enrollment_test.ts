import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

function source(path: string) {
  return readFileSync(resolve(process.cwd(), path), 'utf8')
}

const securityPage = source('app/javascript/pages/Identity/Security/Show.vue')
const english = source('app/javascript/locales/en.ts')
const chinese = source('app/javascript/locales/zh-CN.ts')

test('two-factor enrollment requires current-password reauthentication in the visible form', () => {
  assert.match(securityPage, /totp: \{ password: '', code: '' \}/)
  assert.match(securityPage, /id="confirm_password"[\s\S]*v-model="confirmForm\.totp\.password"/m)
  assert.match(securityPage, /id="confirm_password"[\s\S]*autocomplete="current-password"[\s\S]*required/m)
  assert.match(securityPage, /v-model="confirmForm\.totp\.code"[\s\S]*autocomplete="one-time-code"/m)
  assert.match(securityPage, /identity\.security\.confirmTotpHint/)
})

test('two-factor enrollment explains the cross-device session revocation in both locales', () => {
  assert.match(english, /confirmTotpHint: '.*signs out every other device\.'/)
  assert.match(chinese, /confirmTotpHint: '.*其他设备会全部退出登录。'/)
})
