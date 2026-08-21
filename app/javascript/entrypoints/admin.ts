import { getInitialPageFromDOM } from '@inertiajs/core'
import { createInertiaApp, router } from '@inertiajs/vue3'
import { createApp, h, type DefineComponent } from 'vue'

// Arco Design Vue — unified admin UI library (see docs/UI_COMPONENT_LIBRARY.md)
import '@/styles/shell-foundation.css'
import '@/styles/arco-admin.css'
import { installAdminSpaNavigation } from '@/lib/adminNavigation'
import { csrfHeaders, syncCsrfMetaTag } from '@/lib/csrf'
import { applyPhraseOverrides, createAppI18n, normalizeAppLocale, syncI18nLocale } from '@/lib/i18n'
import { installIntentPrefetch } from '@/lib/intentPrefetch'
import { localeRequestHeaders } from '@/lib/localePreference'

interface InertiaPageLike {
  component?: string
  props?: Record<string, unknown>
}

const pages = import.meta.glob<DefineComponent>('../pages/Admin/**/*.vue')

function inertiaTitle(title: string): string {
  const prefix = document.documentElement.dataset.developerMode === 'true' ? '[DEV] ' : ''
  return `${prefix}${title || 'Mcweb Admin'}`
}

async function bootstrap() {
  const domPage = getInitialPageFromDOM<InertiaPageLike>('app')
  const initialLocale = normalizeAppLocale(
    domPage?.props?.locale ?? document.documentElement.lang,
  )
  const i18n = await createAppI18n(initialLocale)
  applyPhraseOverrides(i18n, initialLocale, domPage?.props?.phrase_overrides)

  const removeAdminSpaNavigation = installAdminSpaNavigation((href) => router.visit(href))
  const removeIntentPrefetch = installIntentPrefetch()
  if (import.meta.hot) {
    import.meta.hot.dispose(() => {
      removeAdminSpaNavigation()
      removeIntentPrefetch()
    })
  }

  const syncLocaleFromInertiaPage = async (page?: InertiaPageLike) => {
    const locale = page?.props?.locale
    if (typeof locale !== 'string' || locale.trim().length === 0) return
    const synchronized = await syncI18nLocale(i18n, locale)
    if (!synchronized) return
    applyPhraseOverrides(i18n, locale, page?.props?.phrase_overrides)
  }

  router.on('before', (event) => {
    const headers = {
      ...csrfHeaders(),
      ...localeRequestHeaders(),
    }

    event.detail.visit.headers = {
      ...headers,
      ...event.detail.visit.headers,
    }
  })

  document.addEventListener('inertia:success', (event) => {
    const detail = (event as CustomEvent<{ page?: InertiaPageLike }>).detail
    const token = detail.page?.props?.csrf_token
    if (typeof token === 'string' && token.length > 0) {
      syncCsrfMetaTag(token)
    } else {
      syncCsrfMetaTag()
    }
  })

  syncCsrfMetaTag()

  await createInertiaApp({
    title: inertiaTitle,
    setup({ el, App, props, plugin }) {
      const initialPage = (props as { initialPage?: InertiaPageLike }).initialPage
      const token = initialPage?.props?.csrf_token
      if (typeof token === 'string' && token.length > 0) {
        syncCsrfMetaTag(token)
      } else {
        syncCsrfMetaTag()
      }
      createApp({ render: () => h(App, props) })
        .use(plugin)
        .use(i18n)
        .mount(el)
    },
    resolve: async (name, targetPage?: InertiaPageLike) => {
      if (!name.startsWith('Admin/')) {
        throw new Error(`Non-admin page must use admin entry: ${name}`)
      }
      const path = `../pages/${name}.vue`
      const loader = pages[path]
      if (!loader) {
        throw new Error(`Admin Inertia page not found: ${name}`)
      }
      await syncLocaleFromInertiaPage(targetPage)
      return loader()
    },
    progress: {
      color: '#38bdf8',
    },
  })
}

void bootstrap()
