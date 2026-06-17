import { createInertiaApp, router } from '@inertiajs/vue3'
import { createApp, h, type DefineComponent } from 'vue'

import '@/styles/portal.css'
import { csrfHeaders, syncCsrfMetaTag } from '@/lib/csrf'

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
})

syncCsrfMetaTag()

createInertiaApp({
  resolve: async (name) => {
    if (!name.startsWith('Admin/')) {
      throw new Error(`Non-admin page must use admin entry: ${name}`)
    }
    const pages = import.meta.glob<DefineComponent>('../pages/Admin/**/*.vue')
    const path = `../pages/${name}.vue`
    const loader = pages[path]
    if (!loader) {
      throw new Error(`Admin Inertia page not found: ${name}`)
    }
    return loader()
  },
  setup({ el, App, props, plugin }) {
    createApp({ render: () => h(App, props) })
      .use(plugin)
      .mount(el)
  },
  progress: {
    color: '#38bdf8',
  },
})
