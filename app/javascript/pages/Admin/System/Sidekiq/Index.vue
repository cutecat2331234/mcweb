<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from 'vue'
import { router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import { IconLaunch, IconRefresh } from '@arco-design/web-vue/es/icon'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { adminRoutes } from '@/lib/adminRoutes'
import {
  adminUrlFromSidekiqFrameUrl,
  isSidekiqAdminReturnUrl,
  normalizeSidekiqFrameUrl,
  normalizeSidekiqStandaloneUrl,
} from '@/lib/sidekiqNavigation'

defineOptions({ layout: AdminLayout })

const props = defineProps<{
  sidekiqUrl: string
}>()

const { t } = useI18n()
const FRAME_DOCUMENT_MARKER = 'meta[name="mcweb-embedded-console"][content="sidekiq"]'
const runtimeOrigin = typeof window === 'undefined'
  ? 'http://mcweb.local'
  : window.location.origin
const initialFrameUrl = normalizeSidekiqFrameUrl(props.sidekiqUrl, runtimeOrigin)
  || `${adminRoutes.sidekiqWeb}/`
const frameKey = ref(0)
const frameElement = ref<HTMLIFrameElement | null>(null)
const frameSrc = ref(initialFrameUrl)
const standaloneUrl = ref(initialFrameUrl)
const frameLoaded = ref(false)
const frameFailed = ref(false)
let loadTimeout: number | undefined
let watchedFrameWindow: Window | null = null

function clearLoadTimeout() {
  if (loadTimeout === undefined) return

  window.clearTimeout(loadTimeout)
  loadTimeout = undefined
}

function scheduleLoadTimeout() {
  clearLoadTimeout()
  loadTimeout = window.setTimeout(() => {
    if (!frameLoaded.value) markFrameFailure()
  }, 15_000)
}

function clearFrameNavigationWatch() {
  if (!watchedFrameWindow) return

  try {
    watchedFrameWindow.removeEventListener('beforeunload', handleFrameNavigationStart)
  }
  catch {
    // The frame can disappear while the parent is being torn down.
  }
  watchedFrameWindow = null
}

function handleFrameNavigationStart() {
  clearFrameNavigationWatch()
  frameLoaded.value = false
  frameFailed.value = false
  scheduleLoadTimeout()
}

function watchFrameNavigation() {
  clearFrameNavigationWatch()
  const childWindow = frameElement.value?.contentWindow
  if (!childWindow) return

  try {
    childWindow.addEventListener('beforeunload', handleFrameNavigationStart, {
      once: true,
    })
    watchedFrameWindow = childWindow
  }
  catch {
    markFrameFailure()
  }
}

function markFrameFailure() {
  clearLoadTimeout()
  clearFrameNavigationWatch()
  frameLoaded.value = false
  frameFailed.value = true
}

function handleFrameLoad() {
  clearFrameNavigationWatch()
  frameLoaded.value = false
  frameFailed.value = false
  scheduleLoadTimeout()

  const frame = frameElement.value
  if (!frame) {
    markFrameFailure()
    return
  }

  let loadedHref: string
  try {
    loadedHref = frame.contentWindow?.location.href || ''
  }
  catch {
    markFrameFailure()
    return
  }

  const origin = window.location.origin
  if (isSidekiqAdminReturnUrl(loadedHref, origin)) {
    window.top?.location.assign(adminRoutes.sidekiq)
    return
  }

  const normalizedStandaloneUrl = normalizeSidekiqStandaloneUrl(loadedHref, origin)
  if (normalizedStandaloneUrl) standaloneUrl.value = normalizedStandaloneUrl

  const normalizedFrameUrl = normalizeSidekiqFrameUrl(loadedHref, origin)
  const adminUrl = normalizedFrameUrl
    ? adminUrlFromSidekiqFrameUrl(normalizedFrameUrl, origin)
    : null
  if (!normalizedFrameUrl || !adminUrl) {
    markFrameFailure()
    return
  }

  try {
    if (!frame.contentDocument?.querySelector(FRAME_DOCUMENT_MARKER)) {
      markFrameFailure()
      return
    }
  }
  catch {
    markFrameFailure()
    return
  }

  clearLoadTimeout()
  frameLoaded.value = true
  frameFailed.value = false
  watchFrameNavigation()

  const currentAdminUrl = `${window.location.pathname}${window.location.search}`
  if (currentAdminUrl !== adminUrl) {
    router.replace({
      url: adminUrl,
      props: currentProps => ({
        ...currentProps,
        sidekiqUrl: normalizedFrameUrl,
      }),
      preserveState: true,
      preserveScroll: true,
    })
  }
}

function handleFrameError() {
  markFrameFailure()
}

function retryFrame() {
  clearFrameNavigationWatch()
  frameLoaded.value = false
  frameFailed.value = false
  frameSrc.value = standaloneUrl.value
  frameKey.value += 1
  scheduleLoadTimeout()
}

onMounted(scheduleLoadTimeout)
onBeforeUnmount(() => {
  clearLoadTimeout()
  clearFrameNavigationWatch()
})
</script>

<template>
  <a-space direction="vertical" :size="16" fill data-testid="admin-sidekiq-page">
    <a-page-header
      :title="t('admin.sidekiq.title')"
      :subtitle="t('admin.sidekiq.subtitle')"
      show-back
      @back="router.visit(adminRoutes.dashboard)"
    >
      <template #extra>
        <a-button
          :href="standaloneUrl"
          target="_blank"
          rel="noopener noreferrer"
          data-admin-hard-navigation
        >
          <template #icon><icon-launch /></template>
          {{ t('admin.sidekiq.openStandalone') }}
        </a-button>
      </template>
    </a-page-header>

    <a-alert
      v-if="frameFailed"
      type="warning"
      show-icon
      role="alert"
      aria-live="assertive"
      :title="t('admin.sidekiq.loadFailedTitle')"
    >
      <a-space direction="vertical" :size="10">
        <span>{{ t('admin.sidekiq.loadFailedDescription') }}</span>
        <a-button size="small" @click="retryFrame">
          <template #icon><icon-refresh /></template>
          {{ t('admin.sidekiq.retry') }}
        </a-button>
      </a-space>
    </a-alert>

    <a-card v-if="!frameFailed" :bordered="true" class="mc-admin-embedded-tool">
      <div
        class="mc-admin-embedded-tool__viewport"
        :aria-busy="!frameLoaded && !frameFailed"
      >
        <div
          v-if="!frameLoaded && !frameFailed"
          class="mc-admin-embedded-tool__status"
          role="status"
        >
          <a-spin :loading="true" :tip="t('admin.sidekiq.loading')" />
        </div>
        <iframe
          ref="frameElement"
          :key="frameKey"
          class="mc-admin-embedded-tool__frame"
          :class="{ 'is-ready': frameLoaded }"
          :src="frameSrc"
          :title="t('admin.sidekiq.frameTitle')"
          :tabindex="frameLoaded ? 0 : -1"
          :aria-hidden="!frameLoaded"
          loading="eager"
          referrerpolicy="same-origin"
          @load="handleFrameLoad"
          @error="handleFrameError"
        />
      </div>
    </a-card>
  </a-space>
</template>
