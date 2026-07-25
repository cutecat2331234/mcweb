<script setup lang="ts">
export interface AdminAlert {
  level: 'info' | 'warning' | 'error'
  message: string
}

defineProps<{
  alerts: AdminAlert[]
}>()

const arcoType: Record<AdminAlert['level'], 'info' | 'warning' | 'error'> = {
  info: 'info',
  warning: 'warning',
  error: 'error',
}
</script>

<template>
  <a-space v-if="alerts.length" direction="vertical" fill class="mb-4">
    <a-alert
      v-for="(alert, index) in alerts"
      :key="index"
      :type="arcoType[alert.level]"
      show-icon
    >
      {{ alert.message }}
    </a-alert>
  </a-space>
</template>
