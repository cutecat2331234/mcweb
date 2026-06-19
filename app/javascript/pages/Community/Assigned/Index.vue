<script setup lang="ts">
import { ref } from 'vue'
import { router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import TopicListTable, { type TopicListItem } from '@/components/portal/TopicListTable.vue'
import BulkModerateToolbar from '@/components/portal/BulkModerateToolbar.vue'
import Select from '@/components/ui/Select.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

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
    return_to: window.location.pathname + window.location.search,
  }, {
    onSuccess: () => { selectedIds.value = [] },
  })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.forum'), href: routes.forum },
    { label: t('forum.assigned.breadcrumb'), current: true },
  ]" />

  <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
    <PageHeader :title="t('forum.assigned.title')" :subtitle="t('forum.assigned.subtitle')" />
    <div class="flex flex-wrap items-center gap-2">
      <Select :model-value="sort" :options="sortOptions" size="sm" @update:model-value="changeSort" />
      <BulkModerateToolbar
        v-if="canBulkModerate && bulkModerateUrl"
        :count="selectedIds.length"
        @moderate="bulkModerate"
      />
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
  <p v-else class="text-sm text-muted-foreground">{{ t('forum.assigned.empty') }}</p>
</template>
