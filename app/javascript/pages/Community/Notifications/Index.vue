<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

export interface NotificationItem {
  id: number
  title: string
  body: string | null
  notification_type: string
  read: boolean
  created_at: string
  url: string | null
  visit_url: string
  mark_read_url: string
}

defineProps<{
  notifications: NotificationItem[]
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
      v-for="notification in notifications"
      :key="notification.id"
      class="rounded-lg border p-4"
      :class="notification.read ? 'opacity-70' : 'border-primary/30 bg-primary/5'"
    >
      <div class="flex items-start justify-between gap-3">
        <div class="min-w-0 flex-1">
          <h3 class="text-sm font-medium">{{ notification.title }}</h3>
          <p v-if="notification.body" class="mt-1 text-sm text-muted-foreground">{{ notification.body }}</p>
          <p class="mt-2 text-xs text-muted-foreground">{{ notification.created_at }}</p>
        </div>
        <div class="flex shrink-0 gap-2">
          <Button v-if="!notification.read" as-child variant="outline" size="sm">
            <Link :href="notification.mark_read_url" method="patch" as="button">已读</Link>
          </Button>
          <Button v-if="notification.url" as-child size="sm">
            <Link :href="notification.visit_url">查看</Link>
          </Button>
        </div>
      </div>
    </article>
  </div>

  <p v-else class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
    暂无通知。
  </p>
</template>
