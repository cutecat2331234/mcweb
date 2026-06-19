import { createInertiaApp, router } from '@inertiajs/vue3'
import { createApp, h, type DefineComponent } from 'vue'

import '@/styles/portal.css'
import { csrfHeaders, syncCsrfMetaTag } from '@/lib/csrf'
import AppProvider from '@/components/AppProvider.vue'

function syncCsrfFromInertiaPage(page?: { props?: Record<string, unknown> }) {
  const token = page?.props?.csrf_token
  if (typeof token === 'string' && token.length > 0) {
    syncCsrfMetaTag(token)
  } else {
    syncCsrfMetaTag()
  }
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
})

syncCsrfMetaTag()

// Wappalyzer 等工具用于识别 Ruby on Rails 的 JS 指纹（Inertia 入口也需设置）
if (typeof window !== 'undefined') {
  ;(window as Window & { _rails_loaded?: boolean })._rails_loaded = true
}

createInertiaApp({
  setup({ el, App, props, plugin }) {
    syncCsrfFromInertiaPage(
      (props as { initialPage?: { props?: Record<string, unknown> } }).initialPage,
    )
    createApp({ render: () => h(AppProvider, null, { default: () => h(App, props) }) })
      .use(plugin)
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
  progress: {
    color: '#38bdf8',
  },
})
