import { getInitialPageFromDOM } from '@inertiajs/core'
import { createInertiaApp, router } from '@inertiajs/vue3'
import { createApp, h, type DefineComponent } from 'vue'

import '@/styles/portal.css'
import { csrfHeaders, syncCsrfMetaTag } from '@/lib/csrf'
import { applyPhraseOverrides, createAppI18n, normalizeAppLocale, syncI18nLocale } from '@/lib/i18n'
import { installIntentPrefetch } from '@/lib/intentPrefetch'
import { installPortalSpaNavigation } from '@/lib/portalNavigation'
import AppProvider from '@/components/AppProvider.vue'

interface InertiaPageLike {
  props?: Record<string, unknown>
}

const pages = import.meta.glob<DefineComponent>([
  '../pages/**/*.vue',
  '!../pages/Admin/**/*.vue',
])

function syncCsrfFromInertiaPage(page?: InertiaPageLike) {
  const token = page?.props?.csrf_token
  if (typeof token === 'string' && token.length > 0) {
    syncCsrfMetaTag(token)
  } else {
    syncCsrfMetaTag()
  }
}

function inertiaTitle(title: string): string {
  const prefix = document.documentElement.dataset.developerMode === 'true' ? '[DEV] ' : ''
  return `${prefix}${title || 'Mcweb'}`
}

async function bootstrap() {
  const domPage = getInitialPageFromDOM<InertiaPageLike>('app')
  const initialLocale = normalizeAppLocale(
    domPage?.props?.locale ?? document.documentElement.lang,
  )
  const i18n = await createAppI18n(initialLocale)
  applyPhraseOverrides(i18n, initialLocale, domPage?.props?.phrase_overrides)

  const removePortalSpaNavigation = installPortalSpaNavigation((href) => router.visit(href))
  const removeIntentPrefetch = installIntentPrefetch()
  if (import.meta.hot) {
    import.meta.hot.dispose(() => {
      removePortalSpaNavigation()
      removeIntentPrefetch()
    })
  }

  const syncLocaleFromInertiaPage = async (page?: InertiaPageLike) => {
    const locale = page?.props?.locale
    await syncI18nLocale(i18n, locale)
    applyPhraseOverrides(i18n, locale, page?.props?.phrase_overrides)
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
    const detail = (event as CustomEvent<{ page?: InertiaPageLike }>).detail
    syncCsrfFromInertiaPage(detail.page)
    void syncLocaleFromInertiaPage(detail.page)
  })

  syncCsrfMetaTag()

  await createInertiaApp({
    title: inertiaTitle,
    setup({ el, App, props, plugin }) {
      const initialPage = (props as { initialPage?: InertiaPageLike }).initialPage
      syncCsrfFromInertiaPage(initialPage)
      void syncLocaleFromInertiaPage(initialPage)
      createApp({ render: () => h(AppProvider, null, { default: () => h(App, props) }) })
        .use(plugin)
        .use(i18n)
        .mount(el)
    },
    resolve: async (name) => {
      if (name.startsWith('Admin/')) {
        throw new Error(`Admin pages must use admin entry: ${name}`)
      }
      const path = `../pages/${name}.vue`
      const loader = pages[path]
      if (!loader) {
        throw new Error(`Inertia page not found: ${name}`)
      }
      return loader()
    },
    progress: false,
  })
}

void bootstrap()
