import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import tailwindcss from '@tailwindcss/vite'
import { vitePluginForArco } from '@arco-plugins/vite-vue'
import RubyPlugin from 'vite-plugin-ruby'
import path from 'path'

function developerBuildBoolean(name: string) {
  if (process.env.MCWEB_DEVELOPER_VITE !== '1') return undefined

  const value = process.env[name]
  if (value === 'enabled') return true
  if (value === 'disabled') return false
  return undefined
}

const developerMinification = developerBuildBoolean('MCWEB_DEVELOPER_VITE_MINIFICATION')
const developerSourceMaps = developerBuildBoolean('MCWEB_DEVELOPER_VITE_SOURCE_MAPS')
const runtimeProfile = process.env.MCWEB_RUNTIME_PROFILE

function mcwebUiArcoStyleBridge() {
  return {
    name: 'mcweb-ui-arco-style-bridge',
    enforce: 'pre' as const,
    transform(code: string, id: string) {
      if (!/\.(?:vue|[cm]?[jt]sx?)(?:$|\?)/.test(id) || !code.includes('@mcweb/ui')) {
        return null
      }

      return {
        code: code.replace(
          /(['"])@mcweb\/ui\1/g,
          '$1@arco-design/web-vue$1',
        ),
        map: null,
      }
    },
  }
}

if (runtimeProfile === 'fast_preview') {
  if (developerMinification === false || developerSourceMaps === true) {
    throw new Error(
      'Fast Preview requires minified assets with public source maps disabled',
    )
  }
}

export default defineConfig({
  plugins: [
    RubyPlugin(),
    mcwebUiArcoStyleBridge(),
    vue(),
    vitePluginForArco({ style: 'css' }),
    tailwindcss(),
  ],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, 'app/javascript'),
      // McWeb unified UI — runtime npm build; repoint to vendor source for 二开 (see docs/UI_COMPONENT_LIBRARY.md)
      '@mcweb/ui': path.resolve(__dirname, 'node_modules/@arco-design/web-vue/es/index.js'),
      '@arco-design/web-vue-source': path.resolve(
        __dirname,
        'vendor/arco-design-vue/packages/web-vue/components/index.ts',
      ),
    },
  },
  build: {
    ...(developerMinification === undefined ? {} : { minify: developerMinification }),
    // vite-plugin-ruby enables production source maps by default. Keep public
    // source maps opt-in so normal production builds do not publish or retain
    // several megabytes of debugging metadata.
    sourcemap: developerSourceMaps ?? false,
  },
})
