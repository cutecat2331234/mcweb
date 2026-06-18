<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
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
  router.get(routes.forumWatchedTagTopics, { sort: value }, { preserveState: true })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: '关注标签', href: routes.forumWatchedTags },
    { label: '标签主题', current: true },
  ]" />

  <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
    <PageHeader title="关注标签的主题" subtitle="来自你关注标签的最新主题" />
    <Select :model-value="sort" :options="sortOptions" size="sm" @update:model-value="changeSort" />
  </div>

  <TopicListTable :topics="topics" show-views show-participants />

  <p v-if="!topics.length" class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
    关注标签后，使用这些标签的新主题会显示在这里。
  </p>

  <Pagination v-if="pagination.pages > 1" :pagination="pagination" :base-path="routes.forumWatchedTagTopics" />
</template>
