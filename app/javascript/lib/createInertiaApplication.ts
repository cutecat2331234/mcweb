import { getInitialPageFromDOM } from '@inertiajs/core'
import { createInertiaApp, router } from '@inertiajs/vue3'
import { createApp, h, type DefineComponent } from 'vue'

import AppProvider from '@/components/AppProvider.vue'
import ApplicationErrorBoundary from '@/components/ApplicationErrorBoundary.vue'
import {
  APPLICATION_SHELL_ADAPTER,
  composeApplicationShell,
  type ApplicationShellAdapter,
} from '@/lib/applicationShell'
import {
  installApplicationNavigation,
  recoverFrontendSafeLocation,
  SAFE_FRONTEND_LOCATION_HEADER,
} from '@/lib/applicationNavigation'
import { csrfHeaders, syncCsrfMetaTag } from '@/lib/csrf'
import {
  assertFrontendComponent,
  frontendApplicationRequestHeaders,
  requireFrontendApplication,
} from '@/lib/frontendApplications'
import {
  loadFrontendApplicationAdapters,
  type FrontendPageLoader,
} from '@/lib/frontendApplicationAdapters'
import { applyPhraseOverrides, createAppI18n, normalizeAppLocale, syncI18nLocale } from '@/lib/i18n'
import { installIntentPrefetch } from '@/lib/intentPrefetch'
import { localeRequestHeaders } from '@/lib/localePreference'
import {
  claimSubmittedForm,
  completeSubmittedForm,
  installUnsavedFormGuards,
  releaseSubmittedForm,
} from '@/lib/unsavedForms'

export type InertiaPageLike = {
  component?: string
  url?: string
  props?: Record<string, unknown>
}

type CreateInertiaApplicationOptions = {
  applicationId: string
  pages: Record<string, FrontendPageLoader>
  titleFallback: string
  progress?: false | { color: string }
  provider?: boolean
  adapterModules?: Record<string, unknown>
  shellAdapter?: ApplicationShellAdapter
  shellAdapterId: string
  uiAdapterId: string
  errorBoundaryId: string
}

function syncCsrfFromPage(page?: InertiaPageLike) {
  const token = page?.props?.csrf_token
  syncCsrfMetaTag(typeof token === 'string' && token.length > 0 ? token : undefined)
}

function applicationErrorCopy() {
  const chinese = document.documentElement.lang.toLowerCase().startsWith('zh')
  return chinese
    ? {
        title: '应用暂时不可用',
        detail: '此应用无法完成加载。请重新载入后再试。',
        reload: '重新载入应用',
      }
    : {
        title: 'Application unavailable',
        detail: 'This application could not finish loading. Reload it and try again.',
        reload: 'Reload application',
      }
}

function bootFailure(applicationId: string, error: unknown) {
  console.error(`[McWeb] ${applicationId} bootstrap failed`, error)
  const root = document.getElementById('app')
  if (!root) throw error
  const copy = applicationErrorCopy()
  root.replaceChildren()
  const main = document.createElement('main')
  main.className = 'mc-application-error'
  main.setAttribute('role', 'alert')
  main.setAttribute('aria-live', 'assertive')
  const heading = document.createElement('h1')
  heading.textContent = copy.title
  const detail = document.createElement('p')
  detail.textContent = copy.detail
  const reload = document.createElement('button')
  reload.type = 'button'
  reload.textContent = copy.reload
  reload.addEventListener('click', () => window.location.reload())
  main.append(heading, detail, reload)
  root.append(main)
}

function runCleanupStack(cleanup: VoidFunction[]): void {
  while (cleanup.length > 0) {
    const remove = cleanup.pop()
    try {
      remove?.()
    } catch (error) {
      console.error('[McWeb] application cleanup failed', error)
    }
  }
}

export async function createMcWebInertiaApplication({
  applicationId,
  pages,
  titleFallback,
  progress = false,
  provider = true,
  adapterModules = {},
  shellAdapter,
  shellAdapterId,
  uiAdapterId,
  errorBoundaryId,
}: CreateInertiaApplicationOptions): Promise<void> {
  const cleanupFunctions: VoidFunction[] = []
  let cleanedUp = false
  let failed = false
  const cleanup = () => {
    if (cleanedUp) return
    cleanedUp = true
    runCleanupStack(cleanupFunctions)
  }
  const failApplication = (error: unknown) => {
    cleanup()
    if (failed) return
    failed = true
    bootFailure(applicationId, error)
  }

  try {
    const descriptor = requireFrontendApplication(applicationId)
    if (descriptor.runtimeKind !== 'inertia' && descriptor.runtimeKind !== 'inertia_document') {
      throw new Error(`Application ${applicationId} cannot boot in the Inertia runtime`)
    }
    if (descriptor.shellAdapter !== shellAdapterId || descriptor.uiAdapter !== uiAdapterId) {
      throw new Error(`Application ${applicationId} entry adapter identities do not match its manifest`)
    }
    if (descriptor.errorBoundaries[0] !== errorBoundaryId) {
      throw new Error(`Application ${applicationId} base error boundary does not match its manifest`)
    }
    if (shellAdapter && shellAdapter.applicationId !== applicationId) {
      throw new Error(`Application ${applicationId} received a foreign shell adapter`)
    }
    const adapters = loadFrontendApplicationAdapters(applicationId, adapterModules)
    cleanupFunctions.push(adapters.dispose)
    for (const path of Object.keys(adapters.pages)) {
      if (pages[path]) {
        throw new Error(`Frontend adapter cannot replace a base page: ${path}`)
      }
    }
    const resolvedPages = { ...pages, ...adapters.pages }
    const effectiveShellAdapter = composeApplicationShell(
      applicationId,
      shellAdapter,
      adapters.navigation,
    )
    const documentApplication = document.documentElement.dataset.mcwebApplication
    if (documentApplication !== applicationId) {
      throw new Error(
        `Document application is ${documentApplication || 'missing'}; entry is ${applicationId}`,
      )
    }

    const domPage = getInitialPageFromDOM<InertiaPageLike>('app')
    if (!domPage?.component) throw new Error(`Initial ${applicationId} page has no component`)
    assertFrontendComponent(applicationId, domPage.component)

    const initialLocale = normalizeAppLocale(
      domPage.props?.locale ?? document.documentElement.lang,
    )
    const i18n = await createAppI18n(initialLocale, descriptor.locales)
    applyPhraseOverrides(i18n, initialLocale, domPage.props?.phrase_overrides)
    await adapters.prepare()
    const removeAdapters = adapters.install()
    cleanupFunctions.push(removeAdapters)

    const syncLocaleFromPage = async (page?: InertiaPageLike) => {
      const locale = page?.props?.locale
      if (typeof locale !== 'string' || locale.trim().length === 0) return
      const synchronized = await syncI18nLocale(i18n, locale)
      if (synchronized) applyPhraseOverrides(i18n, locale, page?.props?.phrase_overrides)
    }

    const removeNavigation = installApplicationNavigation(applicationId)
    cleanupFunctions.push(removeNavigation)
    const removePrefetch = descriptor.runtimeKind === 'inertia'
      ? installIntentPrefetch({ applicationId })
      : () => {}
    cleanupFunctions.push(removePrefetch)
    const removeUnsavedFormGuards = installUnsavedFormGuards()
    cleanupFunctions.push(removeUnsavedFormGuards)

    const removeBeforeHeaders = router.on('before', (event) => {
      event.detail.visit.headers = {
        ...event.detail.visit.headers,
        ...csrfHeaders(),
        ...localeRequestHeaders(),
        ...frontendApplicationRequestHeaders(applicationId),
      }
    })
    cleanupFunctions.push(removeBeforeHeaders)
    const removeStart = router.on('start', (event) => {
      claimSubmittedForm(event.detail.visit.id)
    })
    cleanupFunctions.push(removeStart)
    const onSuccess = (event: Event) => {
      const detail = (event as CustomEvent<{ page?: InertiaPageLike }>).detail
      syncCsrfFromPage(detail.page)
      completeSubmittedForm(
        (event as CustomEvent<{ visitId?: string }>).detail.visitId,
      )
      void syncLocaleFromPage(detail.page)
    }
    document.addEventListener('inertia:success', onSuccess)
    cleanupFunctions.push(() => document.removeEventListener('inertia:success', onSuccess))

    const removeFinish = router.on('finish', (event) => {
      releaseSubmittedForm(event.detail.visit.id)
    })
    cleanupFunctions.push(removeFinish)

    const onHttpException = (event: Event) => {
      const detail = (event as CustomEvent<{
        response?: { status?: number; headers?: Record<string, unknown> }
      }>).detail
      const response = detail?.response
      const safeLocation = Object.entries(response?.headers ?? {})
        .find(([name]) => name.toLowerCase() === SAFE_FRONTEND_LOCATION_HEADER.toLowerCase())?.[1]
      if (response?.status === 409 && recoverFrontendSafeLocation(safeLocation)) {
        event.preventDefault()
        return
      }
      console.warn(`[McWeb] ${applicationId} received an Inertia HTTP exception`, response)
    }
    const onNetworkError = (event: Event) => {
      const detail = (event as CustomEvent<{ error?: unknown }>).detail
      console.warn(`[McWeb] ${applicationId} Inertia network error`, detail?.error)
    }
    document.addEventListener('inertia:httpException', onHttpException)
    document.addEventListener('inertia:networkError', onNetworkError)
    cleanupFunctions.push(() => {
      document.removeEventListener('inertia:httpException', onHttpException)
      document.removeEventListener('inertia:networkError', onNetworkError)
    })

    if (import.meta.hot) {
      import.meta.hot.dispose(() => {
        cleanup()
        window.location.reload()
      })
    }

    syncCsrfFromPage(domPage)
    await createInertiaApp({
      title: (title) => {
        const prefix = document.documentElement.dataset.developerMode === 'true' ? '[DEV] ' : ''
        return `${prefix}${title || titleFallback}`
      },
      setup({ el, App, props, plugin }) {
        const initialPage = (props as { initialPage?: InertiaPageLike }).initialPage
        syncCsrfFromPage(initialPage)
        const applicationContent = adapters.errorBoundaries.reduceRight<() => ReturnType<typeof h>>(
          (child, Boundary) => () => h(Boundary, { applicationId }, { default: child }),
          () => h(App, props),
        )
        const content = () => h(ApplicationErrorBoundary, { applicationId }, {
          default: applicationContent,
        })
        const root = provider
          ? { render: () => h(AppProvider, null, { default: content }) }
          : { render: content }
        const application = createApp(root).use(plugin).use(i18n)
        if (effectiveShellAdapter) {
          application.provide(APPLICATION_SHELL_ADAPTER, effectiveShellAdapter)
        }
        application.mount(el)
        cleanupFunctions.push(() => application.unmount())
      },
      resolve: async (name, targetPage?: InertiaPageLike) => {
        try {
          assertFrontendComponent(applicationId, name)
          const path = `../pages/${name}.vue`
          const loader = resolvedPages[path]
          if (!loader) {
            throw new Error(`Application ${applicationId} has no positive resolver for ${name}`)
          }
          await syncLocaleFromPage(targetPage)
          return await loader()
        } catch (error) {
          failApplication(error)
          throw error
        }
      },
      progress,
    })
  } catch (error) {
    failApplication(error)
  }
}
