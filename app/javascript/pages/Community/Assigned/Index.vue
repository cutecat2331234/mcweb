<script setup lang="ts">
import { router } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import TopicListTable, { type TopicListItem } from '@/components/portal/TopicListTable.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const props = defineProps<{
  topics: TopicListItem[]
  pagination: PaginationMeta
  sort: string
  sortOptions: Array<{ value: string; label: string }>
}>()

function changeSort(value: string) {
  router.get(routes.forumAssigned, { sort: value }, { preserveState: true })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: '指派给我', current: true },
  ]" />

  <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
    <PageHeader title="指派给我" subtitle="Discourse 风格：分配给你处理的主题收件箱" />
    <select
      :value="sort"
      class="h-8 rounded-md border border-input bg-transparent px-2 text-sm"
      @change="changeSort(($event.target as HTMLSelectElement).value)"
    >
      <option v-for="opt in sortOptions" :key="opt.value" :value="opt.value">{{ opt.label }}</option>
    </select>
  </div>

  <TopicListTable :topics="topics" show-views show-participants />
  <Pagination v-if="topics.length" :pagination="pagination" :base-path="routes.forumAssigned" class="mt-4" />
  <p v-else class="text-sm text-muted-foreground">暂无指派给你的主题。</p>
</template>
