import path from 'path'
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import tailwindcss from '@tailwindcss/vite'

/** Standalone Arco admin preview — no Rails / Inertia. */
export default defineConfig({
  root: path.resolve(__dirname, 'demo/arco-admin'),
  plugins: [vue(), tailwindcss()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, 'app/javascript'),
      '@demo': path.resolve(__dirname, 'demo/arco-admin'),
      '@mcweb/ui': path.resolve(__dirname, 'node_modules/@arco-design/web-vue/es/index.js'),
    },
  },
  optimizeDeps: {
    include: ['@arco-design/web-vue'],
  },
  server: {
    port: 5173,
    strictPort: false,
    open: true,
  },
})
