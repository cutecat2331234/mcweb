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
import ListFilterBar from '@/components/portal/ListFilterBar.vue'
import Button from '@/components/ui/Button.vue'
import Select from '@/components/ui/Select.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

const props = defineProps<{
  topics: TopicListItem[]
  pagination: PaginationMeta
  filter: string
  filterOptions: Array<{ value: string; label: string }>
  activeFilters?: Array<{ param: string; label: string; value?: string }>
  windowDays: number
  dismissUrl: string
  canDismiss?: boolean
  canBulkModerate?: boolean
  bulkModerateUrl?: string | null
}>()

const selectedIds = ref<string[]>([])
const dismissing = ref(false)

function changeFilter(value: string) {
  router.get(routes.forumNew, { filter: value || undefined }, { preserveState: true })
}

function removeFilter() {
  router.get(routes.forumNew, {}, { preserveState: true })
}

function dismissAll() {
  if (dismissing.value) return
  if (!window.confirm(t('forum.new.dismissConfirm'))) return
  dismissing.value = true
  router.post(props.dismissUrl, { filter: props.filter || undefined }, {
    onFinish: () => { dismissing.value = false },
  })
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
    { label: t('forum.new.breadcrumb'), current: true },
  ]" />

  <PageHeader :title="t('forum.new.title')" :subtitle="t('forum.new.subtitle', { days: windowDays })" />

  <ListFilterBar :active-filters="activeFilters ?? []" @remove-filter="removeFilter">
    <div class="flex items-center gap-2">
      <label class="text-sm text-muted-foreground">{{ t('forum.lists.filterLabel') }}</label>
      <Select :model-value="filter" :options="filterOptions" size="sm" @update:model-value="changeFilter" />
    </div>
    <Button v-if="canDismiss" variant="outline" size="sm" :disabled="dismissing" @click="dismissAll">
      {{ t('forum.new.dismiss') }}
    </Button>
    <BulkModerateToolbar
      v-if="canBulkModerate && bulkModerateUrl"
      :count="selectedIds.length"
      @moderate="bulkModerate"
    />
  </ListFilterBar>

  <TopicListTable
    v-if="topics.length"
    :topics="topics"
    show-views
    :selectable="!!(canBulkModerate && bulkModerateUrl)"
    :selected-ids="selectedIds"
    @update:selected-ids="selectedIds = $event"
  />
  <p v-else class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">{{ t('forum.new.empty') }}</p>

  <Pagination :pagination="pagination" :base-path="routes.forumNew" />
</template>
