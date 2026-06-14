import { createInertiaApp } from '@inertiajs/vue3'
import { createApp, h, type DefineComponent } from 'vue'

import '@/styles/portal.css'

createInertiaApp({
  resolve: async (name) => {
    const pages = import.meta.glob<DefineComponent>('../pages/**/*.vue')
    const path = `../pages/${name}.vue`
    const loader = pages[path]
    if (!loader) {
      throw new Error(`Inertia page not found: ${name}`)
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
