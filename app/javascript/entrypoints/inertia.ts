import { createInertiaApp, router } from '@inertiajs/vue3'
import { createApp, h, type DefineComponent } from 'vue'

import '@/styles/portal.css'
import { csrfHeaders, syncCsrfMetaTag } from '@/lib/csrf'
import { applyPhraseOverrides, createAppI18n, normalizeAppLocale, syncI18nLocale } from '@/lib/i18n'
import AppProvider from '@/components/AppProvider.vue'

function syncCsrfFromInertiaPage(page?: { props?: Record<string, unknown> }) {
  const token = page?.props?.csrf_token
  if (typeof token === 'string' && token.length > 0) {
    syncCsrfMetaTag(token)
  } else {
    syncCsrfMetaTag()
  }
}

const i18n = createAppI18n()

function syncLocaleFromInertiaPage(page?: { props?: Record<string, unknown> }) {
  syncI18nLocale(i18n, page?.props?.locale)
}

router.on('before', (event) => {
  const headers = csrfHeaders()
  if (Object.keys(headers).length === 0) return

  event.detail.visit.headers = {
    ...event.detail.visit.headers,
    ...headers,
  }
})

document.addEventListener('inertia:success', (event) => {
  const detail = (event as CustomEvent<{ page?: { props?: Record<string, unknown> } }>).detail
  syncCsrfFromInertiaPage(detail.page)
  syncLocaleFromInertiaPage(detail.page)
})

syncCsrfMetaTag()

// Wappalyzer 等工具用于识别 Ruby on Rails 的 JS 指纹（Inertia 入口也需设置）
if (typeof window !== 'undefined') {
  ;(window as Window & { _rails_loaded?: boolean })._rails_loaded = true
}

createInertiaApp({
  setup({ el, App, props, plugin }) {
    const initialPage = (props as { initialPage?: { props?: Record<string, unknown> } }).initialPage
    syncCsrfFromInertiaPage(initialPage)
    const initialLocale = initialPage?.props?.locale ?? normalizeAppLocale(document.documentElement.lang)
    syncI18nLocale(i18n, initialLocale)
    applyPhraseOverrides(i18n, initialLocale, initialPage?.props?.phrase_overrides)
    createApp({ render: () => h(AppProvider, null, { default: () => h(App, props) }) })
      .use(plugin)
      .use(i18n)
      .mount(el)
  },
  resolve: async (name) => {
    if (name.startsWith('Admin/')) {
      throw new Error(`Admin pages must use admin entry: ${name}`)
    }
    const pages = import.meta.glob<DefineComponent>('../pages/**/*.vue')
    const path = `../pages/${name}.vue`
    const loader = pages[path]
    if (!loader) {
      throw new Error(`Inertia page not found: ${name}`)
    }
    return loader()
  },
  progress: false,
})
