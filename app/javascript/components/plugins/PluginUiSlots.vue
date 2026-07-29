<script setup lang="ts">
import { computed } from 'vue'
import { Link, usePage } from '@inertiajs/vue3'

interface PluginUiSlot {
  id: string
  plugin_id: string
  slot: 'dashboard.cards' | 'list.actions' | 'detail.actions' | 'form.fields'
  kind: 'card' | 'action' | 'field'
  title: string
  schema: {
    description?: string
    value?: string | number | boolean
    href?: string
    action_label?: string
    tone?: 'info' | 'success' | 'warning' | 'error'
  }
}

const page = usePage()
const slots = computed(() => {
  const contributions = page.props.plugin_contributions as
    | { ui_slots?: PluginUiSlot[] }
    | undefined
  return contributions?.ui_slots || []
})
</script>

<template>
  <a-space v-if="slots.length" direction="vertical" fill :size="12" class="mb-4">
    <a-row :gutter="[12, 12]">
      <a-col
        v-for="slot in slots.filter((item) => item.kind === 'card')"
        :key="slot.id"
        :xs="24"
        :md="12"
        :xl="8"
      >
        <a-card :title="slot.title" :bordered="true" hoverable>
          <a-statistic v-if="slot.schema.value !== undefined" :value="slot.schema.value" />
          <a-typography-paragraph v-if="slot.schema.description" class="!mb-0">
            {{ slot.schema.description }}
          </a-typography-paragraph>
          <Link
            v-if="slot.schema.href"
            :href="slot.schema.href"
            class="mt-3 inline-block text-[rgb(var(--primary-6))] no-underline hover:underline"
          >
            {{ slot.schema.action_label || slot.title }}
          </Link>
        </a-card>
      </a-col>
    </a-row>

    <a-space v-if="slots.some((item) => item.kind === 'action')" wrap>
      <Link
        v-for="slot in slots.filter((item) => item.kind === 'action' && item.schema.href)"
        :key="slot.id"
        :href="slot.schema.href || '#'"
        class="arco-btn arco-btn-primary arco-btn-size-medium no-underline"
      >
        {{ slot.schema.action_label || slot.title }}
      </Link>
    </a-space>

    <a-descriptions
      v-if="slots.some((item) => item.kind === 'field')"
      :column="{ xs: 1, md: 2 }"
      bordered
    >
      <a-descriptions-item
        v-for="slot in slots.filter((item) => item.kind === 'field')"
        :key="slot.id"
        :label="slot.title"
      >
        {{ slot.schema.value ?? slot.schema.description ?? '—' }}
      </a-descriptions-item>
    </a-descriptions>
  </a-space>
</template>
