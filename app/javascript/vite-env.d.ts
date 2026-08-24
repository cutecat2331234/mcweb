/// <reference types="vite/client" />

declare const __MCWEB_DEVELOPER_BUILD__: boolean

declare module '*.vue' {
  import type { DefineComponent } from 'vue'
  const component: DefineComponent<Record<string, unknown>, Record<string, unknown>, unknown>
  export default component
}
