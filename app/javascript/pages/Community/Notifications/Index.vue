<script setup lang="ts">
import { ref } from 'vue'
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
  category: 'forum' | 'commerce'
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
    category: 'forum' | 'commerce'
  }>
}

const props = defineProps<{
  notifications: NotificationGroup[]
  activeCategory: 'all' | 'forum' | 'commerce'
}>()

const expanded = ref<Record<string, boolean>>({})

function markAllRead() {
  router.patch('/forum/notifications/mark_all_read')
}

function toggleExpand(key: string) {
  expanded.value[key] = !expanded.value[key]
}

function markRead(url: string) {
  router.patch(url, {}, { preserveScroll: true })
}

function switchCategory(category: 'all' | 'forum' | 'commerce') {
  router.get(routes.forumNotifications, { category: category === 'all' ? undefined : category }, { preserveState: true })
}

function categoryLabel(category: string) {
  return category === 'commerce' ? '商城' : '论坛'
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: '通知', current: true },
  ]" />

  <div class="mb-4 flex flex-wrap items-center justify-between gap-4">
    <PageHeader title="通知" subtitle="论坛与商城消息" />
    <Button type="button" variant="outline" size="sm" @click="markAllRead">全部已读</Button>
  </div>

  <div class="mb-4 flex gap-2">
    <Button :variant="activeCategory === 'all' ? 'default' : 'outline'" size="sm" @click="switchCategory('all')">全部</Button>
    <Button :variant="activeCategory === 'forum' ? 'default' : 'outline'" size="sm" @click="switchCategory('forum')">论坛</Button>
    <Button :variant="activeCategory === 'commerce' ? 'default' : 'outline'" size="sm" @click="switchCategory('commerce')">商城</Button>
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
            <Badge variant="outline" class="text-[10px]">{{ categoryLabel(group.category) }}</Badge>
            <h3 class="text-sm font-medium">{{ group.title }}</h3>
            <Badge v-if="group.count > 1">{{ group.count }}</Badge>
            <Badge v-if="group.unread_count" variant="default">{{ group.unread_count }} 未读</Badge>
          </div>
          <p v-if="group.body" class="mt-1 text-sm text-muted-foreground">{{ group.body }}</p>
          <p class="mt-2 text-xs text-muted-foreground">{{ group.latest_at }}</p>
        </div>
        <div class="flex shrink-0 gap-2">
          <Button v-if="group.count > 1" type="button" variant="outline" size="sm" @click="toggleExpand(group.key)">
            {{ expanded[group.key] ? '收起' : '展开' }}
          </Button>
          <Button v-if="group.visit_url" as-child size="sm">
            <Link :href="group.visit_url">查看</Link>
          </Button>
        </div>
      </div>
      <ul v-if="expanded[group.key] && group.items.length" class="mt-3 space-y-2 border-t pt-3">
        <li v-for="item in group.items" :key="item.id" class="flex items-start justify-between gap-2 text-sm">
          <div :class="item.read ? 'text-muted-foreground' : ''">
            <p class="font-medium">{{ item.title }}</p>
            <p v-if="item.body" class="text-xs text-muted-foreground">{{ item.body }}</p>
            <p class="text-xs text-muted-foreground">{{ item.created_at }}</p>
          </div>
          <div class="flex gap-1">
            <Button v-if="!item.read" type="button" variant="outline" size="sm" @click="markRead(item.mark_read_url)">已读</Button>
            <Button as-child size="sm" variant="outline">
              <Link :href="item.visit_url">查看</Link>
            </Button>
          </div>
        </li>
      </ul>
    </article>
  </div>

  <p v-else class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
    暂无通知。
  </p>
</template>
