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
  <a-row justify="center">
    <a-col :xs="24" :md="22" :xl="20">
      <a-space direction="vertical" :size="16" fill>
        <a-page-header
          :title="pluginPage.title"
          :subtitle="pluginPage.description"
          :show-back="false"
        />
        <PluginPageContent :blocks="pluginPage.blocks" />
      </a-space>
    </a-col>
  </a-row>
</template>
