<script setup lang="ts">
export interface AdminAlert {
  level: 'info' | 'warning' | 'error'
  message: string
}

defineProps<{
  alerts: AdminAlert[]
}>()

const levelClass: Record<AdminAlert['level'], string> = {
  info: 'border-sky-200 bg-sky-50 text-sky-900 dark:border-sky-900 dark:bg-sky-950 dark:text-sky-100',
  warning: 'border-amber-200 bg-amber-50 text-amber-900 dark:border-amber-900 dark:bg-amber-950 dark:text-amber-100',
  error: 'border-red-200 bg-red-50 text-red-900 dark:border-red-900 dark:bg-red-950 dark:text-red-100',
}
</script>

<template>
  <div v-if="alerts.length" class="mb-4 space-y-2">
    <p
      v-for="(alert, index) in alerts"
      :key="index"
      class="rounded-md border px-3 py-2 text-sm"
      :class="levelClass[alert.level]"
    >
      {{ alert.message }}
    </p>
  </div>
</template>
