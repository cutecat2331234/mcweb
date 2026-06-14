<script setup lang="ts">
import { router } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import TopicListTable, { type TopicListItem } from '@/components/portal/TopicListTable.vue'
import Button from '@/components/ui/Button.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const props = defineProps<{
  topics: TopicListItem[]
  markAllReadUrl: string
  pagination: PaginationMeta
  sort: string
  sortOptions: Array<{ value: string; label: string }>
}>()

function markAllRead() {
  router.patch(props.markAllReadUrl)
}

function changeSort(value: string) {
  router.get(routes.forumUnread, { sort: value }, { preserveState: true })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: '未读主题', current: true },
  ]" />

  <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
    <PageHeader title="未读主题" subtitle="你有未读回复的主题" />
    <div class="flex flex-wrap items-center gap-2">
      <select
        :value="sort"
        class="h-8 rounded-md border border-input bg-transparent px-2 text-sm"
        @change="changeSort(($event.target as HTMLSelectElement).value)"
      >
        <option v-for="opt in sortOptions" :key="opt.value" :value="opt.value">{{ opt.label }}</option>
      </select>
      <Button v-if="topics.length" type="button" variant="outline" size="sm" @click="markAllRead">
        全部标为已读
      </Button>
    </div>
  </div>

  <TopicListTable :topics="topics" show-views />

  <Pagination v-if="pagination.pages > 1" :pagination="pagination" :base-path="routes.forumUnread" />
</template>
