<script setup lang="ts">
import Button from '@/components/ui/Button.vue'

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
      锁定选中（{{ count }}）
    </Button>
    <Button type="button" variant="outline" size="sm" @click="emit('moderate', 'unlock')">
      解锁选中
    </Button>
    <Button type="button" variant="outline" size="sm" @click="emit('moderate', 'archive')">
      归档选中
    </Button>
    <Button type="button" variant="outline" size="sm" @click="emit('moderate', 'unarchive')">
      取消归档
    </Button>
  </template>
</template>
