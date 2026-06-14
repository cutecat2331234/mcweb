<script setup lang="ts">
import type { HTMLAttributes } from 'vue'
import { cn } from '@/lib/utils'

defineProps<{ class?: HTMLAttributes['class'] }>()
</script>

<template>
  <td :class="cn('p-4 align-middle', $props.class)">
    <slot />
  </td>
</template>
