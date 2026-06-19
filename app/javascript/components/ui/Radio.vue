<script setup lang="ts">
import { cn } from '@/lib/utils'

const props = withDefaults(
  defineProps<{
    modelValue: string
    value: string
    name?: string
    disabled?: boolean
    class?: string
  }>(),
  { disabled: false },
)

const emit = defineEmits<{ 'update:modelValue': [value: string] }>()

function select() {
  if (props.disabled) return
  emit('update:modelValue', props.value)
}
</script>

<template>
  <button
    type="button"
    role="radio"
    :name="name"
    :aria-checked="modelValue === value"
    :disabled="disabled"
    :class="cn(
      'inline-flex h-4 w-4 shrink-0 items-center justify-center rounded-full border border-input bg-background shadow-sm transition-colors',
      'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
      modelValue === value && 'border-primary',
      disabled && 'pointer-events-none opacity-50',
      props.class,
    )"
    @click="select"
  >
    <span
      class="h-2 w-2 rounded-full bg-primary transition-opacity"
      :class="modelValue === value ? 'opacity-100' : 'opacity-0'"
    />
  </button>
</template>
