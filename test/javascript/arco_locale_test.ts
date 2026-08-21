import assert from 'node:assert/strict'
import { existsSync, readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'
import {
  addI18nMessages,
  getLocale,
  useLocale as setArcoLocale,
} from '@arco-design/web-vue/es/locale/index.js'
import enUS from '@arco-design/web-vue/es/locale/lang/en-us.js'
import zhCN from '@arco-design/web-vue/es/locale/lang/zh-cn.js'
import { normalizeAppLocale } from '../../app/javascript/lib/i18nRuntime.ts'

const localePacks = {
  'zh-CN': zhCN,
  en: enUS,
}

test('Arco locale adapter maps normalized application locales', () => {
  const english = localePacks[normalizeAppLocale('EN_gb')]
  const chinese = localePacks[normalizeAppLocale('zh_Hans')]

  assert.equal(english.locale, 'en-US')
  assert.deepEqual(english.modal, { okText: 'Ok', cancelText: 'Cancel' })
  assert.deepEqual(english.drawer, { okText: 'Ok', cancelText: 'Cancel' })
  assert.deepEqual(english.popconfirm, { okText: 'Ok', cancelText: 'Cancel' })

  assert.equal(chinese.locale, 'zh-CN')
  assert.deepEqual(chinese.modal, { okText: '确定', cancelText: '取消' })
  assert.deepEqual(chinese.drawer, { okText: '确定', cancelText: '取消' })
  assert.deepEqual(chinese.popconfirm, { okText: '确定', cancelText: '取消' })
})

test('Arco global fallback is folded into the existing application i18n runtime', () => {
  const runtime = readFileSync(
    resolve(process.cwd(), 'app/javascript/lib/i18n.ts'),
    'utf8',
  )

  assert.equal(existsSync(resolve(process.cwd(), 'app/javascript/lib/arcoLocale.ts')), false)
  assert.match(runtime, /ARCO_LOCALES\[normalizeAppLocale\(locale\)\]/)
  assert.match(runtime, /setArcoLocale\(next\.locale\)/)

  addI18nMessages(
    {
      [zhCN.locale]: zhCN,
      [enUS.locale]: enUS,
    },
    { overwrite: true },
  )
  try {
    setArcoLocale(enUS.locale)
    assert.equal(getLocale(), 'en-US')

    setArcoLocale(zhCN.locale)
    assert.equal(getLocale(), 'zh-CN')
  } finally {
    setArcoLocale(zhCN.locale)
  }
})

test('Arco English locale imports only validation messages into shared shells', () => {
  const viteConfig = readFileSync(resolve(process.cwd(), 'vite.config.ts'), 'utf8')

  assert.match(viteConfig, /function mcwebArcoEnglishLocaleBridge\(\)/)
  assert.match(viteConfig, /mcwebArcoEnglishLocaleBridge\(\)/)
  assert.match(viteConfig, /b-validate\/es\/locale\/en-US\.js/)
  assert.match(viteConfig, /broadValidationImport/)
  assert.match(viteConfig, /filter:\s*\{[\s\S]*?en-us\\\.js\$\//)
  assert.match(
    viteConfig,
    /Arco English locale no longer exposes the expected validation import/,
  )
})

test('every shared Arco shell binds its provider to the vue-i18n locale', () => {
  for (const relativePath of [
    'app/javascript/components/AppProvider.vue',
    'app/javascript/layouts/ArcoAdminLayout.vue',
    'app/javascript/layouts/StaffLayout.vue',
  ]) {
    const source = readFileSync(resolve(process.cwd(), relativePath), 'utf8')

    assert.match(source, /import \{ useArcoLocale \} from '@\/lib\/i18n'/)
    assert.match(source, /const arcoLocale = useArcoLocale\(\)/)
    assert.match(source, /(?:a-config-provider|ConfigProvider) :locale="arcoLocale" global/)
  }
})

test('portal provider keeps Arco controls synchronized with the shared dark theme', () => {
  const source = readFileSync(
    resolve(process.cwd(), 'app/javascript/components/AppProvider.vue'),
    'utf8',
  )

  assert.match(source, /const \{ isDark \} = useTheme\(\)/)
  assert.match(source, /document\.body\.setAttribute\('arco-theme', 'dark'\)/)
  assert.match(source, /document\.body\.removeAttribute\('arco-theme'\)/)
})
