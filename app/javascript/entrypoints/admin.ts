import { createInertiaApp, router } from '@inertiajs/vue3'
import { createApp, h, type DefineComponent } from 'vue'
import ArcoVue from '@mcweb/ui'

import '@/styles/portal.css'
// Arco Design Vue — unified admin UI library (see docs/UI_COMPONENT_LIBRARY.md)
import '@arco-design/web-vue/dist/arco.css'
import '@/styles/arco-admin.css'
import { installAdminSpaNavigation } from '@/lib/adminNavigation'
import { csrfHeaders, syncCsrfMetaTag } from '@/lib/csrf'
import { applyPhraseOverrides, createAppI18n, normalizeAppLocale, syncI18nLocale } from '@/lib/i18n'

const pages = import.meta.glob<DefineComponent>('../pages/Admin/**/*.vue')

const i18n = createAppI18n()

const removeAdminSpaNavigation = installAdminSpaNavigation((href) => router.visit(href))
if (import.meta.hot) {
  import.meta.hot.dispose(removeAdminSpaNavigation)
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
  const token = detail.page?.props?.csrf_token
  if (typeof token === 'string' && token.length > 0) {
    syncCsrfMetaTag(token)
  } else {
    syncCsrfMetaTag()
  }
  syncI18nLocale(i18n, detail.page?.props?.locale)
})

syncCsrfMetaTag()

createInertiaApp({
  setup({ el, App, props, plugin }) {
    const initialPage = (props as { initialPage?: { props?: Record<string, unknown> } }).initialPage
    const token = initialPage?.props?.csrf_token
    if (typeof token === 'string' && token.length > 0) {
      syncCsrfMetaTag(token)
    } else {
      syncCsrfMetaTag()
    }
    const initialLocale = initialPage?.props?.locale ?? normalizeAppLocale(document.documentElement.lang)
    syncI18nLocale(i18n, initialLocale)
    applyPhraseOverrides(i18n, initialLocale, initialPage?.props?.phrase_overrides)
    createApp({ render: () => h(App, props) })
      .use(plugin)
      .use(i18n)
      .use(ArcoVue)
      .mount(el)
  },
  resolve: async (name) => {
    if (!name.startsWith('Admin/')) {
      throw new Error(`Non-admin page must use admin entry: ${name}`)
    }
    const path = `../pages/${name}.vue`
    const loader = pages[path]
    if (!loader) {
      throw new Error(`Admin Inertia page not found: ${name}`)
    }
    return loader()
  },
  progress: {
    color: '#38bdf8',
  },
})
