<script setup lang="ts">
import type { HTMLAttributes } from 'vue'
import { cn } from '@/lib/utils'

const model = defineModel<string | number>()

defineOptions({ inheritAttrs: false })

withDefaults(defineProps<{
  class?: HTMLAttributes['class']
  type?: string
  placeholder?: string
  autocomplete?: string
  required?: boolean
  autofocus?: boolean
  density?: 'default' | 'comfortable'
}>(), {
  density: 'default',
})
</script>

<template>
  <input
    v-bind="$attrs"
    v-model="model"
    :type="type ?? 'text'"
    :placeholder="placeholder"
    :autocomplete="autocomplete"
    :required="required"
    :autofocus="autofocus"
    :class="cn(
      'flex w-full rounded-md border border-input bg-transparent shadow-sm transition-colors placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:cursor-not-allowed disabled:opacity-50',
      density === 'comfortable' ? 'h-11 px-3.5 py-2 text-base sm:text-sm' : 'h-9 px-3 py-1 text-sm',
      $props.class,
    )"
  >
</template>
