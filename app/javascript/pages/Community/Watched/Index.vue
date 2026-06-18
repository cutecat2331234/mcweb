<script setup lang="ts">
import { router } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import TopicListTable, { type TopicListItem } from '@/components/portal/TopicListTable.vue'
import Select from '@/components/ui/Select.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const props = defineProps<{
  topics: TopicListItem[]
  pagination: PaginationMeta
  sort: string
  sortOptions: Array<{ value: string; label: string }>
}>()

function changeSort(value: string) {
  router.get(routes.forumWatching, { sort: value }, { preserveState: true })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: '关注主题', current: true },
  ]" />

  <PageHeader title="关注主题" subtitle="你正在关注的主题" />

  <div class="mb-4 flex items-center gap-2">
    <label class="text-sm text-muted-foreground">排序：</label>
    <Select :model-value="sort" :options="sortOptions" size="sm" @update:model-value="changeSort" />
  </div>

  <TopicListTable :topics="topics" show-views />

  <Pagination :pagination="pagination" :base-path="routes.forumWatching" />
</template>
