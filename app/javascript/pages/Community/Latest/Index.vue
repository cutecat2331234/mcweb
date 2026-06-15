<script setup lang="ts">
import { ref } from 'vue'
import { Link, router } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import TopicListTable, { type TopicListItem } from '@/components/portal/TopicListTable.vue'
import BulkModerateToolbar from '@/components/portal/BulkModerateToolbar.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const props = defineProps<{
  topics: TopicListItem[]
  pagination: PaginationMeta
  sort: string
  filter: string
  filterOptions: Array<{ value: string; label: string }>
  activeFilters?: Array<{ param: string; label: string; value?: string }>
  rss_url: string
  canBulkModerate?: boolean
  bulkModerateUrl?: string | null
}>()

const selectedIds = ref<string[]>([])

const sortOptions = [
  { value: 'activity', label: '最近活跃' },
  { value: 'hot', label: '热门' },
  { value: 'newest', label: '最新发布' },
  { value: 'replies', label: '最多回复' },
  { value: 'views', label: '最多浏览' },
]

function changeSort(value: string) {
  router.get(routes.forumLatest, { sort: value, filter: props.filter || undefined }, { preserveState: true })
}

function changeFilter(value: string) {
  router.get(routes.forumLatest, { sort: props.sort, filter: value || undefined }, { preserveState: true })
}

function removeFilter() {
  router.get(routes.forumLatest, { sort: props.sort }, { preserveState: true })
}

function bulkModerate(action: string) {
  if (!props.bulkModerateUrl || selectedIds.value.length === 0) return
  router.patch(props.bulkModerateUrl, {
    topic_ids: selectedIds.value,
    action_type: action,
    return_to: window.location.pathname + window.location.search,
  }, {
    onSuccess: () => { selectedIds.value = [] },
  })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: '最新', current: true },
  ]" />

  <PageHeader title="最新主题" subtitle="全站最近活跃的主题" />

  <div class="mb-4 flex flex-wrap items-center gap-4">
    <div class="flex items-center gap-2">
      <label class="text-sm text-muted-foreground">排序：</label>
      <select
        :value="sort"
        class="h-8 rounded-md border border-input bg-transparent px-2 text-sm"
        @change="changeSort(($event.target as HTMLSelectElement).value)"
      >
        <option v-for="opt in sortOptions" :key="opt.value" :value="opt.value">{{ opt.label }}</option>
      </select>
    </div>
    <div class="flex items-center gap-2">
      <label class="text-sm text-muted-foreground">筛选：</label>
      <select
        :value="filter"
        class="h-8 rounded-md border border-input bg-transparent px-2 text-sm"
        @change="changeFilter(($event.target as HTMLSelectElement).value)"
      >
        <option v-for="opt in filterOptions" :key="opt.value" :value="opt.value">{{ opt.label }}</option>
      </select>
    </div>
    <BulkModerateToolbar
      v-if="canBulkModerate && bulkModerateUrl"
      :count="selectedIds.length"
      @moderate="bulkModerate"
    />
    <a :href="rss_url" target="_blank" rel="noopener" class="text-sm text-muted-foreground hover:text-foreground">RSS 订阅</a>
  </div>

  <div v-if="activeFilters?.length" class="mb-4 flex flex-wrap items-center gap-2">
    <span class="text-xs text-muted-foreground">已选筛选：</span>
    <span
      v-for="chip in activeFilters"
      :key="`${chip.param}-${chip.value || chip.label}`"
      class="inline-flex items-center gap-1 rounded-full border border-primary/30 bg-primary/5 px-2.5 py-0.5 text-xs text-primary"
    >
      {{ chip.label }}
      <button type="button" class="hover:opacity-70" title="移除此筛选" @click="removeFilter">×</button>
    </span>
  </div>

  <TopicListTable
    :topics="topics"
    show-views
    :selectable="!!(canBulkModerate && bulkModerateUrl)"
    :selected-ids="selectedIds"
    @update:selected-ids="selectedIds = $event"
  />

  <Pagination :pagination="pagination" :base-path="routes.forumLatest" />
</template>
