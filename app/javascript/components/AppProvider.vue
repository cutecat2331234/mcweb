<script setup lang="ts">
import { ConfigProvider } from '@mcweb/ui'
import ConfirmDialog from '@/components/ui/ConfirmDialog.vue'
import PromptDialog from '@/components/ui/PromptDialog.vue'
import { useArcoLocale } from '@/lib/i18n'

const arcoLocale = useArcoLocale()
</script>

<template>
  <ConfigProvider :locale="arcoLocale" global>
    <ConfirmDialog />
    <PromptDialog />
    <slot />
  </ConfigProvider>
</template>
