import { createApp } from 'vue'
import ArcoVue from '@mcweb/ui'
import App from './App.vue'

import '@arco-design/web-vue/dist/arco.css'
import '@/styles/arco-admin.css'
import './demo.css'

createApp(App).use(ArcoVue).mount('#app')
