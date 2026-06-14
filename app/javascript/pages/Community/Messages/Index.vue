<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Badge from '@/components/ui/Badge.vue'
import Button from '@/components/ui/Button.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

defineProps<{
  conversations: Array<{
    id: number
    url: string
    other_username: string
    avatar_url: string
    last_message_at: string | null
    last_message_preview: string | null
    unread_count: number
  }>
}>()
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: '私信', current: true },
  ]" />

  <div class="mb-4 flex items-center justify-between">
    <PageHeader title="私信" subtitle="与站友一对一交流" />
    <Button as-child size="sm">
      <Link :href="routes.forumMessagesNew">发私信</Link>
    </Button>
  </div>

  <div v-if="conversations.length" class="divide-y rounded-lg border">
    <Link
      v-for="conv in conversations"
      :key="conv.id"
      :href="conv.url"
      class="flex items-center gap-3 p-4 no-underline hover:bg-muted/50"
    >
      <img :src="conv.avatar_url" :alt="conv.other_username" class="h-10 w-10 rounded-full" />
      <div class="min-w-0 flex-1">
        <div class="flex items-center justify-between gap-2">
          <span class="font-medium text-foreground">{{ conv.other_username }}</span>
          <span class="text-xs text-muted-foreground">{{ conv.last_message_at || '' }}</span>
        </div>
        <p class="truncate text-sm text-muted-foreground">{{ conv.last_message_preview || '暂无消息' }}</p>
      </div>
      <Badge v-if="conv.unread_count > 0" variant="danger">{{ conv.unread_count }}</Badge>
    </Link>
  </div>
  <p v-else class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
    暂无私信。点击「发私信」开始对话。
  </p>
</template>
