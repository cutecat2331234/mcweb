import { createInertiaApp } from '@inertiajs/vue3'
import { createApp, h, type DefineComponent } from 'vue'

import '@/styles/portal.css'

// Wappalyzer 等工具用于识别 Ruby on Rails 的 JS 指纹（Inertia 入口也需设置）
if (typeof window !== 'undefined') {
  ;(window as Window & { _rails_loaded?: boolean })._rails_loaded = true
}

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
