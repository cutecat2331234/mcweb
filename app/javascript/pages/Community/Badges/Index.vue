<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Badge from '@/components/ui/Badge.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

interface BadgeItem {
  name: string
  slug: string
  icon: string
  color: string
  description: string | null
  grant_rule_label: string
  users_count: number
  url: string
}

defineProps<{
  badges: BadgeItem[]
}>()
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: '徽章画廊', current: true },
  ]" />

  <PageHeader title="徽章画廊" subtitle="探索社区成就徽章，了解获得方式（对标 Discourse / XenForo）" />

  <div v-if="badges.length" class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
    <Link
      v-for="badge in badges"
      :key="badge.slug"
      :href="badge.url"
      class="rounded-lg border p-4 transition-colors hover:bg-muted/50"
    >
      <div class="flex items-start gap-3">
        <span class="text-2xl" :style="{ color: badge.color }">{{ badge.icon }}</span>
        <div class="min-w-0 flex-1">
          <h2 class="font-semibold" :style="{ color: badge.color }">{{ badge.name }}</h2>
          <p v-if="badge.description" class="mt-1 text-sm text-muted-foreground">{{ badge.description }}</p>
          <div class="mt-2 flex flex-wrap gap-2">
            <Badge variant="secondary">{{ badge.grant_rule_label }}</Badge>
            <Badge variant="outline">{{ badge.users_count }} 人获得</Badge>
          </div>
        </div>
      </div>
    </Link>
  </div>
  <p v-else class="text-sm text-muted-foreground">暂无徽章。</p>
</template>
