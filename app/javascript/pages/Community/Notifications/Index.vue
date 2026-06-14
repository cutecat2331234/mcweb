<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Badge from '@/components/ui/Badge.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

export interface NotificationGroup {
  key: string
  notification_type: string
  title: string
  body: string | null
  count: number
  unread_count: number
  read: boolean
  latest_at: string
  visit_url: string | null
  items: Array<{
    id: number
    title: string
    body: string | null
    created_at: string
    visit_url: string
    mark_read_url: string
    read: boolean
  }>
}

defineProps<{
  notifications: NotificationGroup[]
}>()

function markAllRead() {
  router.patch('/forum/notifications/mark_all_read')
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: '通知', current: true },
  ]" />

  <div class="mb-4 flex items-center justify-between gap-4">
    <PageHeader title="通知" subtitle="主题回复与系统消息" />
    <Button type="button" variant="outline" size="sm" @click="markAllRead">全部已读</Button>
  </div>

  <div v-if="notifications.length" class="space-y-2">
    <article
      v-for="group in notifications"
      :key="group.key"
      class="rounded-lg border p-4"
      :class="group.read ? 'opacity-70' : 'border-primary/30 bg-primary/5'"
    >
      <div class="flex items-start justify-between gap-3">
        <div class="min-w-0 flex-1">
          <div class="flex items-center gap-2">
            <h3 class="text-sm font-medium">{{ group.title }}</h3>
            <Badge v-if="group.count > 1">{{ group.count }}</Badge>
            <Badge v-if="group.unread_count" variant="default">{{ group.unread_count }} 未读</Badge>
          </div>
          <p v-if="group.body" class="mt-1 text-sm text-muted-foreground">{{ group.body }}</p>
          <p class="mt-2 text-xs text-muted-foreground">{{ group.latest_at }}</p>
        </div>
        <Button v-if="group.visit_url" as-child size="sm">
          <Link :href="group.visit_url">查看</Link>
        </Button>
      </div>
    </article>
  </div>

  <p v-else class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
    暂无通知。
  </p>
</template>
