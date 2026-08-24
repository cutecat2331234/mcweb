<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { IconLaunch, IconRefresh } from '@arco-design/web-vue/es/icon'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { adminRoutes } from '@/lib/adminRoutes'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()
const frameKey = ref(0)
const frameLoaded = ref(false)
const frameFailed = ref(false)
let loadTimeout: number | undefined

function clearLoadTimeout() {
  if (loadTimeout === undefined) return

  window.clearTimeout(loadTimeout)
  loadTimeout = undefined
}

function scheduleLoadTimeout() {
  clearLoadTimeout()
  loadTimeout = window.setTimeout(() => {
    if (!frameLoaded.value) frameFailed.value = true
  }, 15_000)
}

function handleFrameLoad() {
  clearLoadTimeout()
  frameLoaded.value = true
  frameFailed.value = false
}

function handleFrameError() {
  clearLoadTimeout()
  frameLoaded.value = false
  frameFailed.value = true
}

function retryFrame() {
  frameLoaded.value = false
  frameFailed.value = false
  frameKey.value += 1
  scheduleLoadTimeout()
}

onMounted(scheduleLoadTimeout)
onBeforeUnmount(clearLoadTimeout)
</script>

<template>
  <a-space direction="vertical" :size="16" fill data-testid="admin-sidekiq-page">
    <a-page-header
      :title="t('admin.sidekiq.title')"
      :subtitle="t('admin.sidekiq.subtitle')"
      :show-back="false"
    >
      <template #extra>
        <a-button
          :href="adminRoutes.sidekiqWeb"
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

    <a-card :bordered="true" class="mc-admin-embedded-tool">
      <div
        class="mc-admin-embedded-tool__viewport"
        :aria-busy="!frameLoaded"
      >
        <div
          v-if="!frameLoaded && !frameFailed"
          class="mc-admin-embedded-tool__status"
          role="status"
        >
          <a-spin :loading="true" :tip="t('admin.sidekiq.loading')" />
        </div>
        <iframe
          :key="frameKey"
          class="mc-admin-embedded-tool__frame"
          :src="adminRoutes.sidekiqWeb"
          :title="t('admin.sidekiq.frameTitle')"
          loading="eager"
          @load="handleFrameLoad"
          @error="handleFrameError"
        />
      </div>
    </a-card>
  </a-space>
</template>
