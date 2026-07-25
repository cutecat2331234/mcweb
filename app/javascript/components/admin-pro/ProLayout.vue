<script setup lang="ts">
/**
 * Backward-compatible alias retained for third-party pages that imported the
 * former proof-of-concept layout. The implementation is now the canonical
 * Arco admin shell.
 */
import ArcoAdminLayout from '@/layouts/ArcoAdminLayout.vue'
</script>

<template>
  <ArcoAdminLayout>
    <slot />
  </ArcoAdminLayout>
</template>
