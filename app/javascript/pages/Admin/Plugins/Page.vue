<script setup lang="ts">
import AdminLayout from '@/layouts/AdminLayout.vue'
import PluginPageContent, {
  type PluginPageBlock,
} from '@/components/plugins/PluginPageContent.vue'

defineOptions({ layout: AdminLayout })

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
  <div class="min-w-0">
    <a-page-header
      :title="pluginPage.title"
      :subtitle="pluginPage.description"
      :show-back="false"
      class="mb-4 !px-0"
    />
    <PluginPageContent :blocks="pluginPage.blocks" />
  </div>
</template>
