<script setup lang="ts">
import { Link } from '@inertiajs/vue3'

export interface PluginPageBlock {
  type: 'stat' | 'text' | 'alert' | 'links' | 'description_list'
  title?: string
  label?: string
  value?: string | number | boolean
  body?: string
  tone?: 'info' | 'success' | 'warning' | 'error'
  items?: Array<{ label: string; value?: string | number | boolean; href?: string }>
}

defineProps<{
  blocks: PluginPageBlock[]
}>()

function alertType(tone?: PluginPageBlock['tone']) {
  return tone || 'info'
}
</script>

<template>
  <a-space direction="vertical" fill :size="16">
    <template v-for="(block, index) in blocks" :key="`${block.type}-${index}`">
      <a-card
        v-if="block.type === 'stat'"
        :title="block.title"
        :bordered="true"
        hoverable
      >
        <a-statistic :title="block.label" :value="block.value ?? '—'" />
      </a-card>

      <a-card
        v-else-if="block.type === 'text'"
        :title="block.title"
        :bordered="true"
      >
        <a-typography-paragraph class="!mb-0 whitespace-pre-wrap">
          {{ block.body }}
        </a-typography-paragraph>
      </a-card>

      <a-alert
        v-else-if="block.type === 'alert'"
        :type="alertType(block.tone)"
        :title="block.title"
        show-icon
      >
        {{ block.body }}
      </a-alert>

      <a-card
        v-else-if="block.type === 'links'"
        :title="block.title"
        :bordered="true"
      >
        <a-list :bordered="false" size="small">
          <a-list-item v-for="item in block.items" :key="item.href">
            <Link :href="item.href || '#'" class="text-[rgb(var(--primary-6))] no-underline hover:underline">
              {{ item.label }}
            </Link>
          </a-list-item>
        </a-list>
      </a-card>

      <a-card
        v-else-if="block.type === 'description_list'"
        :title="block.title"
        :bordered="true"
      >
        <a-descriptions :column="{ xs: 1, sm: 2, lg: 3 }" bordered>
          <a-descriptions-item
            v-for="item in block.items"
            :key="item.label"
            :label="item.label"
          >
            {{ item.value }}
          </a-descriptions-item>
        </a-descriptions>
      </a-card>
    </template>

    <a-empty v-if="blocks.length === 0" />
  </a-space>
</template>
