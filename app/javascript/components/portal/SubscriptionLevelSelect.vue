<script setup lang="ts">
import { computed, ref } from 'vue'
import { router } from '@inertiajs/vue3'
import Select from '@/components/ui/Select.vue'

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

const processing = ref(false)

const currentValue = computed(() => {
  if (!props.watching) return 'off'
  return props.notificationLevel || 'watching'
})

const currentDescription = computed(() =>
  props.options.find((opt) => opt.value === currentValue.value)?.description
)

function onChange(level: string) {
  if (level === currentValue.value || processing.value) return
  processing.value = true
  router.patch(props.subscriptionUrl, { level }, {
    preserveScroll: true,
    onFinish: () => { processing.value = false },
  })
}
</script>

<template>
  <Select
    :model-value="currentValue"
    :options="options"
    :title="currentDescription"
    size="sm"
    :disabled="processing"
    class="min-w-[7.5rem]"
    @update:model-value="onChange"
  />
</template>
