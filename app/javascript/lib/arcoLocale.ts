import { computed, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import {
  addI18nMessages,
  useLocale as setArcoLocale,
} from '@arco-design/web-vue/es/locale/index.js'
import enUS from '@arco-design/web-vue/es/locale/lang/en-us.js'
import zhCN from '@arco-design/web-vue/es/locale/lang/zh-cn.js'
import type { ArcoLang } from '@arco-design/web-vue/es/locale/interface.js'
import { normalizeAppLocale, type AppLocale } from './i18nRuntime'

const ARCO_LOCALES = {
  'zh-CN': zhCN,
  en: enUS,
} satisfies Record<AppLocale, ArcoLang>

addI18nMessages(
  {
    [zhCN.locale]: zhCN,
    [enUS.locale]: enUS,
  },
  { overwrite: true },
)

export function resolveArcoLocale(locale: unknown): ArcoLang {
  return ARCO_LOCALES[normalizeAppLocale(locale)]
}

export function syncArcoLocale(locale: unknown): ArcoLang {
  const next = resolveArcoLocale(locale)
  // Static services such as Modal.confirm render outside the component tree.
  setArcoLocale(next.locale)
  return next
}

export function useArcoLocale() {
  const { locale } = useI18n()
  const arcoLocale = computed(() => resolveArcoLocale(locale.value))

  watch(
    locale,
    (next) => {
      syncArcoLocale(next)
    },
    { immediate: true },
  )

  return arcoLocale
}
