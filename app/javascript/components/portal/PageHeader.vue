<script setup lang="ts">
defineProps<{
  title: string
  subtitle?: string
}>()
</script>

<template>
  <header class="mb-6">
    <h1 class="text-2xl font-semibold tracking-tight">{{ title }}</h1>
    <p v-if="subtitle" class="mt-1 text-sm text-muted-foreground">{{ subtitle }}</p>
  </header>
</template>
