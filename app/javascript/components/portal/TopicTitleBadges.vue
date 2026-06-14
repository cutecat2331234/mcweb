<script setup lang="ts">
import Badge from '@/components/ui/Badge.vue'

defineProps<{
  pinned?: boolean
  featured?: boolean
  locked?: boolean
  solved?: boolean
  hasUnread?: boolean
  unreadCount?: number
}>()
</script>

<template>
  <span v-if="pinned" class="mr-1 text-xs text-amber-600">[置顶]</span>
  <span v-if="featured" class="mr-1 text-xs text-blue-600">[精选]</span>
  <span v-if="locked" class="mr-1 text-xs text-muted-foreground">[锁定]</span>
  <span v-if="solved" class="mr-1 text-xs text-green-600">[已解决]</span>
  <Badge v-if="hasUnread" class="ml-2">{{ unreadCount }} 未读</Badge>
</template>
