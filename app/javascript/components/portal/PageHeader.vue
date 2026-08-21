<script setup lang="ts">
import { cn } from '@/lib/utils'

withDefaults(defineProps<{
  title: string
  subtitle?: string
  density?: 'default' | 'compact'
}>(), {
  density: 'default',
})
</script>

<template>
  <div
    :class="cn(
      'page-header flex flex-col sm:flex-row sm:items-end sm:justify-between',
      density === 'compact' ? 'mb-6 gap-3 pb-0' : 'mb-8 gap-4 pb-6',
    )"
  >
    <div class="min-w-0 space-y-1">
      <h1 class="text-2xl font-bold text-foreground sm:text-3xl">{{ title }}</h1>
      <p v-if="subtitle" class="text-sm leading-6 text-muted-foreground sm:text-base">{{ subtitle }}</p>
    </div>
    <div v-if="$slots.actions" class="flex shrink-0 flex-wrap items-center gap-2">
      <slot name="actions" />
    </div>
  </div>
</template>
