<script setup lang="ts">
import WebsiteLayout from '@/layouts/WebsiteLayout.vue'
import PluginPageContent, {
  type PluginPageBlock,
} from '@/components/plugins/PluginPageContent.vue'

defineOptions({ layout: WebsiteLayout })

defineProps<{
  pluginPage: {
    id: string
    plugin_id: string
    title: string
    description?: string
    blocks: PluginPageBlock[]
  }
}>()
</script>

<template>
  <div class="mx-auto max-w-6xl px-4 py-10 sm:py-14">
    <a-page-header
      :title="pluginPage.title"
      :subtitle="pluginPage.description"
      :show-back="false"
      class="mb-5 !px-0"
    />
    <PluginPageContent :blocks="pluginPage.blocks" />
  </div>
</template>
