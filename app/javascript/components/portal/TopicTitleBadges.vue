<script setup lang="ts">
import Badge from '@/components/ui/Badge.vue'
import { Link } from '@inertiajs/vue3'

defineProps<{
  prefix?: string | null
  pinned?: boolean
  featured?: boolean
  locked?: boolean
  solved?: boolean
  wiki?: boolean
  globalAnnouncement?: boolean
  unlisted?: boolean
  hasUnread?: boolean
  unreadCount?: number
  linkedProduct?: boolean
  linkedProductName?: string | null
  linkedProductUrl?: string | null
  tags?: Array<{ name: string; slug: string; url: string }>
}>()
</script>

<template>
  <span v-if="prefix" class="mr-1 text-xs text-violet-600">[{{ prefix }}]</span>
  <span v-if="pinned" class="mr-1 text-xs text-amber-600">[置顶]</span>
  <span v-if="featured" class="mr-1 text-xs text-blue-600">[精选]</span>
  <span v-if="locked" class="mr-1 text-xs text-muted-foreground">[锁定]</span>
  <span v-if="wiki" class="mr-1 text-xs text-cyan-600">[Wiki]</span>
  <span v-if="globalAnnouncement" class="mr-1 text-xs text-rose-600">[公告]</span>
  <span v-if="unlisted" class="mr-1 text-xs text-violet-600">[未列出]</span>
  <span v-if="solved" class="mr-1 text-xs text-green-600">[已解决]</span>
  <Link v-if="linkedProduct && linkedProductUrl" :href="linkedProductUrl" class="mr-1 text-xs text-emerald-600 hover:underline" @click.stop>[商品]</Link>
  <Link
    v-for="tag in tags || []"
    :key="tag.slug"
    :href="tag.url"
    class="mr-1 text-xs text-sky-600 hover:underline"
    @click.stop
  >#{{ tag.name }}</Link>
  <Badge v-if="hasUnread" class="ml-2">{{ unreadCount }} 未读</Badge>
</template>
