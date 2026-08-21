<script setup lang="ts">
import { vAccessibleFormControlNames } from '@/directives/arcoAccessibility'
import ArcoAdminLayout from '@/layouts/ArcoAdminLayout.vue'
</script>

<template>
  <ArcoAdminLayout v-accessible-form-control-names>
    <slot />
  </ArcoAdminLayout>
</template>
