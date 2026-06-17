<script setup lang="ts">
defineProps<{
  title: string
  subtitle?: string
}>()
</script>

<template>
  <header class="mb-8 flex flex-col gap-4 border-b pb-6 sm:flex-row sm:items-end sm:justify-between">
    <div class="min-w-0 space-y-1">
      <h1 class="text-2xl font-semibold tracking-tight text-foreground sm:text-3xl">{{ title }}</h1>
      <p v-if="subtitle" class="text-sm text-muted-foreground sm:text-base">{{ subtitle }}</p>
    </div>
    <div v-if="$slots.actions" class="flex shrink-0 flex-wrap items-center gap-2">
      <slot name="actions" />
    </div>
  </header>
</template>
