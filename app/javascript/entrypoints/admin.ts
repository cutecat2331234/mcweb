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

document.addEventListener('inertia:success', () => {
  syncCsrfMetaTag()
})

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
