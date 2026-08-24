import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

function source(path: string) {
  return readFileSync(resolve(process.cwd(), path), 'utf8')
}

const identityDocumentLayout = source(
  'app/javascript/layouts/account/IdentityDocumentLayout.vue',
)
const accountManifest = source('config/frontend_applications/base/account.json')
const pageHeader = source('app/javascript/components/portal/PageHeader.vue')
const label = source('app/javascript/components/ui/Label.vue')
const input = source('app/javascript/components/ui/Input.vue')
const button = source('app/javascript/components/ui/Button.vue')
const signIn = source('app/javascript/pages/Identity/Sessions/New.vue')

const publicAuthPages = [
  'app/javascript/pages/Identity/Sessions/New.vue',
  'app/javascript/pages/Identity/Sessions/TwoFactor.vue',
  'app/javascript/pages/Identity/Registrations/New.vue',
  'app/javascript/pages/Identity/PasswordResets/New.vue',
  'app/javascript/pages/Identity/PasswordResets/Edit.vue',
  'app/javascript/pages/Identity/EmailVerificationResends/New.vue',
  'app/javascript/pages/Identity/TotpRecoveries/New.vue',
  'app/javascript/pages/Identity/TotpRecoveries/Edit.vue',
]

test('public authentication layout uses a centered bounded surface', () => {
  assert.match(identityDocumentLayout, /justify-center/)
  assert.match(identityDocumentLayout, /max-w-lg/)
  assert.match(identityDocumentLayout, /data-testid="auth-surface"/)
  assert.match(identityDocumentLayout, /from '@mcweb\/ui'/)
  assert.match(identityDocumentLayout, /<Layout/)
  assert.match(identityDocumentLayout, /<LayoutHeader/)
  assert.match(identityDocumentLayout, /<LayoutContent/)
  assert.match(identityDocumentLayout, /<Card/)
  assert.match(identityDocumentLayout, /padding: '24px'/)
  assert.match(identityDocumentLayout, /<FlashMessages/)
  assert.match(identityDocumentLayout, /<LanguageSwitcher/)
  assert.match(identityDocumentLayout, /toggleTheme/)
  assert.match(identityDocumentLayout, /@arco-design\/web-vue\/es\/icon/)
  assert.doesNotMatch(identityDocumentLayout, /@lucide\/vue/)
  assert.doesNotMatch(identityDocumentLayout, /WebsiteLayout/)
  assert.match(identityDocumentLayout, /<a :href="routes\.home"/)
  assert.match(identityDocumentLayout, /<Button[^>]+:href="routes\.forum"/)
  assert.match(identityDocumentLayout, /<Button[^>]+:href="routes\.store"/)
  assert.match(identityDocumentLayout, /t\('nav\.forum'\)/)
  assert.match(identityDocumentLayout, /t\('nav\.store'\)/)
  assert.doesNotMatch(identityDocumentLayout, /t\('website\./)
  assert.doesNotMatch(identityDocumentLayout, /\bLink\b|router\.visit/)
  assert.doesNotMatch(identityDocumentLayout, /components\/ui\/Button/)
})

test('public identity documents belong to the account application shell', () => {
  assert.match(accountManifest, /"component_prefixes": \["Account\/", "Identity\/", "Minecraft\/"\]/)
  assert.match(accountManifest, /"\/app\/identity\/sign-in"/)
  assert.match(accountManifest, /"Identity\/Sessions\/New"/)

  for (const path of publicAuthPages) {
    const page = source(path)
    assert.match(page, /@\/layouts\/account\/IdentityDocumentLayout\.vue/, path)
    assert.match(page, /defineOptions\(\{ layout: IdentityDocumentLayout \}\)/, path)
    assert.doesNotMatch(page, /WebsiteLayout|@\/layouts\/Website/, path)
  }
})

test('shared form primitives expose stable label rhythm and comfortable controls', () => {
  assert.match(label, /block text-sm font-medium leading-5/)
  assert.doesNotMatch(label, /leading-none/)
  assert.match(input, /density\?: 'default' \| 'comfortable'/)
  assert.match(input, /'h-11 px-3\.5 py-2 text-base sm:text-sm'/)
  assert.match(button, /comfortable: 'h-11 rounded-md px-5 text-sm'/)
})

test('public authentication pages opt into compact headings', () => {
  for (const path of publicAuthPages) {
    if (path === 'app/javascript/pages/Identity/Sessions/New.vue') continue
    assert.match(source(path), /<PageHeader[\s\S]*?density="compact"/m, path)
  }

  assert.match(signIn, /PageHeader,[\s\S]*from '@mcweb\/ui'/m)
  assert.match(signIn, /<PageHeader[\s\S]*:show-back="false"/m)
  assert.match(pageHeader, /density\?: 'default' \| 'compact'/)
  assert.match(pageHeader, /density === 'compact' \? 'mb-6 gap-3 pb-0'/)
  assert.doesNotMatch(pageHeader, /tracking-tight/)
})

test('sign-in form uses the shared Arco library for stable field and action geometry', () => {
  assert.match(signIn, /from '@mcweb\/ui'/)
  assert.match(signIn, /<Form[\s\S]*layout="vertical"[\s\S]*size="large"/m)
  assert.equal((signIn.match(/<FormItem/g) || []).length, 3)
  assert.match(signIn, /<Input[\s\S]*id="email"/m)
  assert.match(signIn, /<InputPassword[\s\S]*id="password"/m)
  assert.match(signIn, /<Checkbox v-model="form\.session\.remember_me">/)
  assert.match(signIn, /html-type="submit"[\s\S]*size="large"[\s\S]*long/m)
  assert.doesNotMatch(signIn, /@\/components\/ui\//)
  assert.doesNotMatch(signIn, /gradient|translate[XY]?\(/i)
})
