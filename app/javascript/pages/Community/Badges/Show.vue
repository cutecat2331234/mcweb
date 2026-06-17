<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import Badge from '@/components/ui/Badge.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

interface BadgeInfo {
  name: string
  slug: string
  icon: string
  color: string
  description: string | null
  grant_rule_label: string
  users_count: number
  url: string
}

interface Holder {
  username: string
  display_name: string | null
  avatar_url: string | null
  profile_url: string
  granted_at: string
}

const props = defineProps<{
  badge: BadgeInfo
  holders: Holder[]
  pagination: PaginationMeta
}>()
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: '徽章画廊', href: routes.forumBadges },
    { label: badge.name, current: true },
  ]" />

  <div class="mb-6 flex items-start gap-4">
    <span class="text-4xl" :style="{ color: badge.color }">{{ badge.icon }}</span>
    <div>
      <PageHeader :title="badge.name" :subtitle="badge.description || undefined" />
      <div class="mt-2 flex flex-wrap gap-2">
        <Badge variant="secondary">{{ badge.grant_rule_label }}</Badge>
        <Badge variant="outline">{{ badge.users_count }} 人获得</Badge>
      </div>
    </div>
  </div>

  <h2 class="mb-3 text-sm font-semibold">获得者</h2>
  <div v-if="holders.length" class="divide-y rounded-lg border">
    <div v-for="holder in holders" :key="holder.username" class="flex items-center justify-between gap-3 px-4 py-3">
      <Link :href="holder.profile_url" class="flex items-center gap-2 hover:underline">
        <img
          v-if="holder.avatar_url"
          :src="holder.avatar_url"
          :alt="holder.username"
          class="h-8 w-8 rounded-full"
        />
        <span class="font-medium">{{ holder.display_name || holder.username }}</span>
        <span class="text-sm text-muted-foreground">@{{ holder.username }}</span>
      </Link>
      <span class="text-xs text-muted-foreground">{{ holder.granted_at }}</span>
    </div>
  </div>
  <p v-else class="text-sm text-muted-foreground">暂无人获得此徽章。</p>

  <Pagination
    v-if="pagination.pages > 1"
    :pagination="pagination"
    :base-path="routes.forumBadge(badge.slug)"
    class="mt-4"
  />
</template>
