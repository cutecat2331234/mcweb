<script setup lang="ts">
import { computed } from 'vue'
import { router } from '@inertiajs/vue3'

export interface SubscriptionLevelOption {
  value: string
  label: string
  description?: string
}

const props = defineProps<{
  options: SubscriptionLevelOption[]
  subscriptionUrl: string
  watching: boolean
  notificationLevel?: 'watching' | 'tracking' | 'normal' | null
}>()

const currentValue = computed(() => {
  if (!props.watching) return 'off'
  return props.notificationLevel || 'watching'
})

const currentDescription = computed(() =>
  props.options.find((opt) => opt.value === currentValue.value)?.description
)

function onChange(event: Event) {
  const level = (event.target as HTMLSelectElement).value
  router.patch(props.subscriptionUrl, { level }, { preserveScroll: true })
}
</script>

<template>
  <select
    :value="currentValue"
    class="h-8 rounded-md border border-input bg-transparent px-2 text-sm"
    :title="currentDescription || undefined"
    @change="onChange"
  >
    <option v-for="opt in options" :key="opt.value" :value="opt.value">{{ opt.label }}</option>
  </select>
</template>
