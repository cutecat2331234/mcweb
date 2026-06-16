<script setup lang="ts">
import { watchEffect } from 'vue'
import { useActiveTemplate } from '@/lib/useActiveTemplate'

const { activeTemplate } = useActiveTemplate()

watchEffect(() => {
  const faviconUrl = activeTemplate.value?.faviconUrl
  if (!faviconUrl) return

  let link = document.querySelector<HTMLLinkElement>("link[rel='icon']")
  if (!link) {
    link = document.createElement('link')
    link.rel = 'icon'
    document.head.appendChild(link)
  }
  link.href = faviconUrl
})
</script>

<template>
  <template v-if="activeTemplate?.cssUrls?.length">
    <link
      v-for="(href, index) in activeTemplate.cssUrls"
      :key="`${activeTemplate.key}-${index}`"
      rel="stylesheet"
      :href="href"
    >
  </template>
</template>
