<script setup lang="ts">
import { shallowRef, watch, watchEffect, type Component } from 'vue'
import { ConfigProvider } from '@mcweb/ui'
import { useArcoLocale } from '@/lib/i18n'
import { confirmState, resolveConfirm } from '@/lib/useConfirm'
import { promptState, resolvePrompt } from '@/lib/usePrompt'
import { useTheme } from '@/lib/useTheme'

const arcoLocale = useArcoLocale()
const { isDark } = useTheme()
const ConfirmDialog = shallowRef<Component>()
const PromptDialog = shallowRef<Component>()

// Closed global dialogs are not startup UI. Retain each component after its
// first use so closing transitions and subsequent opens keep their lifecycle.
// Request identity also observes same-tick retries and prevents an old import
// failure from settling a newer request.
watch(
  () => confirmState.resolve,
  async (request) => {
    if (!request || ConfirmDialog.value) return
    try {
      ConfirmDialog.value = (await import('@/components/ui/ConfirmDialog.vue')).default
    } catch (error) {
      resolveConfirm(false, request)
      console.error('[McWeb] confirmation dialog failed to load', error)
    }
  },
  { immediate: true },
)

watch(
  () => promptState.resolve,
  async (request) => {
    if (!request || PromptDialog.value) return
    try {
      PromptDialog.value = (await import('@/components/ui/PromptDialog.vue')).default
    } catch (error) {
      resolvePrompt(null, request)
      console.error('[McWeb] prompt dialog failed to load', error)
    }
  },
  { immediate: true },
)

watchEffect(() => {
  if (typeof document === 'undefined') return
  if (isDark.value) {
    document.body.setAttribute('arco-theme', 'dark')
  } else {
    document.body.removeAttribute('arco-theme')
  }
})
</script>

<template>
  <ConfigProvider :locale="arcoLocale" global>
    <component :is="ConfirmDialog" v-if="ConfirmDialog" />
    <component :is="PromptDialog" v-if="PromptDialog" />
    <slot />
  </ConfigProvider>
</template>
