<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import TopicListTable, { type TopicListItem } from '@/components/portal/TopicListTable.vue'
import SubscriptionLevelSelect, { type SubscriptionLevelOption } from '@/components/portal/SubscriptionLevelSelect.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const props = defineProps<{
  tag: {
    name: string
    slug: string
    description?: string | null
    color_hex?: string | null
    rss_url: string
    watching?: boolean
    notification_level?: 'watching' | 'tracking' | 'normal' | null
    subscription_url?: string
  }
  topics: TopicListItem[]
  pagination: PaginationMeta
  loggedIn?: boolean
  sort?: string
  subscriptionLevels?: SubscriptionLevelOption[]
}>()

const sortOptions = [
  { value: 'activity', label: '最近活跃' },
  { value: 'hot', label: '热门' },
  { value: 'newest', label: '最新发布' },
  { value: 'replies', label: '最多回复' },
  { value: 'views', label: '最多浏览' },
]

function changeSort(value: string) {
  router.get(`/app/forum/tags/${props.tag.slug}`, { sort: value }, { preserveState: true })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: `标签：${tag.name}`, current: true },
  ]" />

  <div v-if="tag.color_hex" class="mb-4 h-1 w-full max-w-xl rounded-full" :style="{ backgroundColor: tag.color_hex }" />

  <div class="mb-4 flex flex-wrap items-start justify-between gap-3">
    <PageHeader :title="`#${tag.name}`" subtitle="按标签浏览主题" />
    <SubscriptionLevelSelect
      v-if="loggedIn && tag.subscription_url && subscriptionLevels?.length"
      :options="subscriptionLevels"
      :subscription-url="tag.subscription_url"
      :watching="!!tag.watching"
      :notification-level="tag.notification_level"
    />
  </div>

  <p v-if="tag.description" class="mb-4 text-sm text-muted-foreground">{{ tag.description }}</p>

  <p class="mb-4">
    <a :href="tag.rss_url" target="_blank" rel="noopener" class="text-sm text-muted-foreground hover:text-foreground">RSS 订阅</a>
  </p>

  <div class="mb-4 flex items-center gap-2">
    <label class="text-sm text-muted-foreground">排序：</label>
    <select
      :value="sort || 'activity'"
      class="h-8 rounded-md border border-input bg-transparent px-2 text-sm"
      @change="changeSort(($event.target as HTMLSelectElement).value)"
    >
      <option v-for="opt in sortOptions" :key="opt.value" :value="opt.value">{{ opt.label }}</option>
    </select>
  </div>

  <TopicListTable :topics="topics" show-views />

  <Pagination :pagination="pagination" :base-path="`/app/forum/tags/${tag.slug}`" />
</template>
