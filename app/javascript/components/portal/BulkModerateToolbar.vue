<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import Button from '@/components/ui/Button.vue'

const { t } = useI18n()

defineProps<{
  count: number
}>()

const emit = defineEmits<{
  moderate: [action: string]
}>()
</script>

<template>
  <template v-if="count > 0">
    <Button type="button" variant="outline" size="sm" @click="emit('moderate', 'lock')">
      {{ t('components.bulkModerate.lockSelected', { count }) }}
    </Button>
    <Button type="button" variant="outline" size="sm" @click="emit('moderate', 'unlock')">
      {{ t('components.bulkModerate.unlockSelected') }}
    </Button>
    <Button type="button" variant="outline" size="sm" @click="emit('moderate', 'archive')">
      {{ t('components.bulkModerate.archiveSelected') }}
    </Button>
    <Button type="button" variant="outline" size="sm" @click="emit('moderate', 'unarchive')">
      {{ t('components.bulkModerate.unarchiveSelected') }}
    </Button>
  </template>
</template>
