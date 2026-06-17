<script setup lang="ts">
import type { HTMLAttributes } from 'vue'
import { cn } from '@/lib/utils'

const props = defineProps<{
  class?: HTMLAttributes['class']
  fallback?: string
}>()
</script>

<template>
  <div
    :class="cn(
      'relative flex h-9 w-9 shrink-0 overflow-hidden rounded-full bg-muted text-sm font-medium text-muted-foreground',
      props.class,
    )"
  >
    <slot>
      <span class="flex h-full w-full items-center justify-center uppercase">
        {{ fallback?.slice(0, 2) || '?' }}
      </span>
    </slot>
  </div>
</template>
