<script setup lang="ts">
import { Alert } from '@mcweb/ui'

defineProps<{
  title: string
  message: string
}>()
</script>

<template>
  <Alert
    type="warning"
    :title="title"
    data-testid="developer-mode-banner"
    role="alert"
    show-icon
    banner
  >
    {{ message }}
  </Alert>
</template>
