import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import tailwindcss from '@tailwindcss/vite'
import { vitePluginForArco } from '@arco-plugins/vite-vue'
import RubyPlugin from 'vite-plugin-ruby'
import { existsSync } from 'node:fs'
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
const developerBuild = process.env.MCWEB_DEVELOPER_VITE === '1'
const runtimeProfile = process.env.MCWEB_RUNTIME_PROFILE

const arcoRuntimeMarker = '/node_modules/@arco-design/web-vue/es/'
const arcoRuntimeRoot = path.resolve(__dirname, 'node_modules/@arco-design/web-vue/es')

function isVueRuntime(id: string) {
  const normalized = id.replace(/\\/g, '/')
  return normalized.includes('/node_modules/vue/') ||
    normalized.includes('/node_modules/@vue/')
}

type ArcoChunkGroupPlan = {
  name: string
  areas?: string
  icons?: string
  packages?: string
  paths?: string
}

// Keep the public component areas readable and enumerate only the shared Arco
// internals that would otherwise become one-request chunks. The build contract
// below makes an Arco upgrade fail loudly when one of those internals moves.
const arcoChunkPlan: readonly ArcoChunkGroupPlan[] = [
  {
    name: 'arco-provider-runtime',
    areas: 'config-provider',
    paths: '_utils/global-config.js _utils/is.js _virtual/plugin-vue_export-helper.js',
  },
  {
    name: 'arco-auth-shell',
    areas: 'button card spin',
    icons: 'icon-loading',
    paths: '_hooks/use-form-item.js _hooks/use-size.js _utils/omit.js _utils/vue-utils.js form/context.js',
  },
  {
    name: 'arco-sign-in-form',
    areas: 'alert checkbox divider form grid input page-header space tooltip trigger',
    icons: 'icon-check-circle-fill icon-close icon-close-circle-fill icon-empty icon-exclamation-circle-fill icon-eye icon-eye-invisible icon-info-circle-fill icon-left icon-question-circle icon-search',
    packages: 'compute-scroll-into-view resize-observer-polyfill scroll-into-view-if-needed',
    paths: '_components/client-only.js _components/feedback-icon.js _components/icon-hover.js _components/resize-observer.js _components/resize-observer-v2.js _hooks/use-cursor.js _hooks/use-first-element.js _hooks/use-index.js _hooks/use-merge-state.js _hooks/use-overflow.js _hooks/use-pick-slots.js _hooks/use-popup-manager.js _hooks/use-resize-observer.js _hooks/use-state.js _hooks/use-teleport-container.js _utils/constant.js _utils/dom.js _utils/get-value-by-path.js _utils/keyboard.js _utils/keycode.js _utils/pick.js _utils/raf.js _utils/responsive-observe.js _utils/throttle-by-raf.js',
  },
  {
    name: 'arco-data-display',
    areas: 'avatar descriptions empty popover statistic tag typography',
    icons: 'icon-copy icon-edit icon-image-close',
  },
  {
    name: 'arco-extended-form',
    areas: 'input-number switch tabs textarea',
    icons: 'icon-minus icon-plus icon-up',
  },
  { name: 'arco-developer-tools', areas: 'back-top drawer message watermark' },
  {
    name: 'arco-settings-icons',
    icons: 'icon-apps icon-book icon-experiment icon-link icon-lock icon-safe icon-storage icon-thunderbolt',
  },
]

function chunkTokens(value?: string) {
  return new Set(value?.split(/\s+/).filter(Boolean) ?? [])
}

function assertArcoChunkPlan() {
  for (const group of arcoChunkPlan) {
    const targets = [
      ...chunkTokens(group.areas),
      ...[...chunkTokens(group.icons)].map((icon) => `icon/${icon}/index.js`),
      ...chunkTokens(group.paths),
    ]
    for (const target of targets) {
      if (!existsSync(path.resolve(arcoRuntimeRoot, target))) {
        throw new Error(`Arco chunk group ${group.name} references missing runtime path: ${target}`)
      }
    }
    for (const packageName of chunkTokens(group.packages)) {
      if (!existsSync(path.resolve(__dirname, 'node_modules', packageName, 'package.json'))) {
        throw new Error(`Arco chunk group ${group.name} references missing dependency: ${packageName}`)
      }
    }
  }
}

assertArcoChunkPlan()

const arcoChunkGroups = arcoChunkPlan.map((group) => ({
  name: group.name,
  areas: chunkTokens(group.areas),
  icons: chunkTokens(group.icons),
  packages: chunkTokens(group.packages),
  paths: chunkTokens(group.paths),
}))

function arcoRuntimePath(id: string) {
  const normalized = id.replace(/\\/g, '/')
  const markerIndex = normalized.indexOf(arcoRuntimeMarker)
  return markerIndex === -1
    ? undefined
    : normalized.slice(markerIndex + arcoRuntimeMarker.length).split('?')[0]
}

function isRuntimeChunkGroup(id: string, group: (typeof arcoChunkGroups)[number]) {
  const runtimePath = arcoRuntimePath(id)
  if (runtimePath) {
    const [area, detail] = runtimePath.split('/')
    if (group.areas.has(area) ||
      (area === 'icon' && group.icons.has(detail)) ||
      group.paths.has(runtimePath)) return true
  }

  const normalized = id.replace(/\\/g, '/')
  return [...group.packages].some((packageName) =>
    normalized.includes(`/node_modules/${packageName}/`),
  )
}

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

function mcwebArcoEnglishLocaleBridge() {
  const broadValidationImport =
    /import\s*\{\s*DefaultValidateMessage\s*\}\s*from\s*(['"])b-validate\1;?/

  return {
    name: 'mcweb-arco-english-locale-bridge',
    enforce: 'pre' as const,
    transform: {
      filter: {
        id: /@arco-design[\\/]web-vue[\\/]es[\\/]locale[\\/]lang[\\/]en-us\.js$/,
      },
      handler(code: string) {
        if (!broadValidationImport.test(code)) {
          throw new Error('Arco English locale no longer exposes the expected validation import')
        }

        return {
          // Arco only reads the default English messages here. Importing the
          // package root also pulls the complete validator into every shell and
          // creates a redundant initial request for pages that do not validate.
          code: code.replace(
            broadValidationImport,
            "import DefaultValidateMessage from 'b-validate/es/locale/en-US.js';",
          ),
          map: null,
        }
      },
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
  define: {
    __MCWEB_DEVELOPER_BUILD__: JSON.stringify(developerBuild),
  },
  plugins: [
    RubyPlugin(),
    mcwebUiArcoStyleBridge(),
    mcwebArcoEnglishLocaleBridge(),
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
    rolldownOptions: {
      output: {
        codeSplitting: {
          groups: [
            {
              name: 'vue-runtime',
              test: isVueRuntime,
              includeDependenciesRecursively: false,
            },
            ...arcoChunkGroups.map((group) => ({
              name: group.name,
              test: (id: string) => isRuntimeChunkGroup(id, group),
              includeDependenciesRecursively: false,
            })),
          ],
        },
      },
    },
  },
})
