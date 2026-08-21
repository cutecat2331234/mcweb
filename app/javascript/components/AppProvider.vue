<script setup lang="ts">
import { watchEffect } from 'vue'
import { ConfigProvider } from '@mcweb/ui'
import ConfirmDialog from '@/components/ui/ConfirmDialog.vue'
import PromptDialog from '@/components/ui/PromptDialog.vue'
import { useArcoLocale } from '@/lib/i18n'
import { useTheme } from '@/lib/useTheme'

const arcoLocale = useArcoLocale()
const { isDark } = useTheme()

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
    <ConfirmDialog />
    <PromptDialog />
    <slot />
  </ConfigProvider>
</template>
