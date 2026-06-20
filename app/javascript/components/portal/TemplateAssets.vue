<script setup lang="ts">
import { watchEffect } from 'vue'
import { useActiveTemplate } from '@/lib/useActiveTemplate'

withDefaults(
  defineProps<{
    /** 门户布局由 PortalLayout 控制样式，默认不注入模板 CSS，避免 website 主题覆盖顶栏 */
    includeCss?: boolean
  }>(),
  { includeCss: true },
)

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
  <template v-if="includeCss && activeTemplate?.cssUrls?.length">
    <link
      v-for="(href, index) in activeTemplate.cssUrls"
      :key="`${activeTemplate.key}-${index}`"
      rel="stylesheet"
      :href="href"
    >
  </template>
</template>
