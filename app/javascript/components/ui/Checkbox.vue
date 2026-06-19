<script setup lang="ts">
import { computed } from 'vue'
import { Check } from '@lucide/vue'
import { cn } from '@/lib/utils'

const props = withDefaults(
  defineProps<{
    modelValue: boolean
    disabled?: boolean
    id?: string
    class?: string
  }>(),
  { disabled: false },
)

const emit = defineEmits<{ 'update:modelValue': [value: boolean] }>()

const checked = computed({
  get: () => props.modelValue,
  set: (value: boolean) => emit('update:modelValue', value),
})

function toggle() {
  if (props.disabled) return
  checked.value = !checked.value
}
</script>

<template>
  <button
    :id="id"
    type="button"
    role="checkbox"
    :aria-checked="checked"
    :disabled="disabled"
    :class="cn(
      'inline-flex h-4 w-4 shrink-0 items-center justify-center rounded border border-input bg-background shadow-sm transition-colors',
      'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
      checked && 'border-primary bg-primary text-primary-foreground',
      disabled && 'pointer-events-none opacity-50',
      props.class,
    )"
    @click="toggle"
  >
    <Check v-if="checked" class="h-3 w-3" />
  </button>
</template>
