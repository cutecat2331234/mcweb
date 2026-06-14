<script setup lang="ts">
import type { HTMLAttributes } from 'vue'
import { cn } from '@/lib/utils'

const model = defineModel<string>()

defineProps<{
  class?: HTMLAttributes['class']
  rows?: number
  placeholder?: string
  required?: boolean
  id?: string
}>()
</script>

<template>
  <textarea
    :id="id"
    v-model="model"
    :rows="rows ?? 4"
    :placeholder="placeholder"
    :required="required"
    :class="cn(
      'flex min-h-[80px] w-full rounded-md border border-input bg-transparent px-3 py-2 text-sm shadow-sm placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:cursor-not-allowed disabled:opacity-50',
      $props.class,
    )"
  />
</template>
