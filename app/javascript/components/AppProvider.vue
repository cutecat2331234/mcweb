<script setup lang="ts">
import ConfirmDialog from '@/components/ui/ConfirmDialog.vue'
import PromptDialog from '@/components/ui/PromptDialog.vue'
</script>

<template>
  <ConfirmDialog />
  <PromptDialog />
  <slot />
</template>
