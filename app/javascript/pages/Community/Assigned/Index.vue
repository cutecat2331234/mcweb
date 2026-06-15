<script setup lang="ts">
import { ref } from 'vue'
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
  pagination: PaginationMeta
  sort: string
  sortOptions: Array<{ value: string; label: string }>
  canBulkModerate?: boolean
  bulkModerateUrl?: string | null
}>()

const selectedIds = ref<string[]>([])

function changeSort(value: string) {
  router.get(routes.forumAssigned, { sort: value }, { preserveState: true })
}

function bulkModerate(action: string) {
  if (!props.bulkModerateUrl || selectedIds.value.length === 0) return
  router.patch(props.bulkModerateUrl, {
    topic_ids: selectedIds.value,
    action_type: action,
  }, {
    onSuccess: () => { selectedIds.value = [] },
  })
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
    <div class="flex flex-wrap items-center gap-2">
      <select
        :value="sort"
        class="h-8 rounded-md border border-input bg-transparent px-2 text-sm"
        @change="changeSort(($event.target as HTMLSelectElement).value)"
      >
        <option v-for="opt in sortOptions" :key="opt.value" :value="opt.value">{{ opt.label }}</option>
      </select>
      <template v-if="canBulkModerate && bulkModerateUrl && selectedIds.length">
        <Button type="button" variant="outline" size="sm" @click="bulkModerate('lock')">
          锁定选中（{{ selectedIds.length }}）
        </Button>
        <Button type="button" variant="outline" size="sm" @click="bulkModerate('archive')">
          归档选中
        </Button>
      </template>
    </div>
  </div>

  <TopicListTable
    :topics="topics"
    show-views
    show-participants
    :selectable="!!(canBulkModerate && bulkModerateUrl)"
    :selected-ids="selectedIds"
    @update:selected-ids="selectedIds = $event"
  />
  <Pagination v-if="topics.length" :pagination="pagination" :base-path="routes.forumAssigned" class="mt-4" />
  <p v-else class="text-sm text-muted-foreground">暂无指派给你的主题。</p>
</template>
