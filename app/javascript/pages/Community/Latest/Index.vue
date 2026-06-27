<script setup lang="ts">
import { ref, computed } from 'vue'
import { Link, router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import TopicListTable, { type TopicListItem } from '@/components/portal/TopicListTable.vue'
import BulkModerateToolbar from '@/components/portal/BulkModerateToolbar.vue'
import ListFilterBar from '@/components/portal/ListFilterBar.vue'
import Select from '@/components/ui/Select.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

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

const sortOptions = computed(() => [
  { value: 'activity', label: t('forum.latest.sortActivity') },
  { value: 'hot', label: t('forum.latest.sortHot') },
  { value: 'newest', label: t('forum.latest.sortNewest') },
  { value: 'replies', label: t('forum.latest.sortReplies') },
  { value: 'views', label: t('forum.latest.sortViews') },
])

function changeSort(value: string) {
  router.get(routes.forumLatest, { sort: value, filter: props.filter || undefined }, { preserveState: true })
}

function changeFilter(value: string) {
  router.get(routes.forumLatest, { sort: props.sort, filter: value || undefined }, { preserveState: true })
}

function removeFilter(chip: { param: string }) {
  router.get(routes.forumLatest, {
    sort: chip.param === 'sort' ? undefined : (props.sort === 'activity' ? undefined : props.sort),
    filter: chip.param === 'filter' ? undefined : (props.filter || undefined),
  }, { preserveState: true })
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
    { label: t('forum.latest.breadcrumb'), current: true },
  ]" />

  <PageHeader :title="t('forum.latest.title')" :subtitle="t('forum.latest.subtitle')" />

  <ListFilterBar :active-filters="activeFilters ?? []" @remove-filter="removeFilter">
    <div class="flex items-center gap-2">
      <label class="text-sm text-muted-foreground">{{ t('forum.lists.sortLabel') }}</label>
      <Select :model-value="sort" :options="sortOptions" size="sm" @update:model-value="changeSort" />
    </div>
    <div class="flex items-center gap-2">
      <label class="text-sm text-muted-foreground">{{ t('forum.lists.filterLabel') }}</label>
      <Select :model-value="filter" :options="filterOptions" size="sm" @update:model-value="changeFilter" />
    </div>
    <BulkModerateToolbar
      v-if="canBulkModerate && bulkModerateUrl"
      :count="selectedIds.length"
      @moderate="bulkModerate"
    />
    <template #rss>
      <a :href="rss_url" target="_blank" rel="noopener" class="text-sm text-muted-foreground hover:text-foreground">{{ t('forum.lists.rss') }}</a>
    </template>
  </ListFilterBar>

  <TopicListTable
    :topics="topics"
    show-views
    :selectable="!!(canBulkModerate && bulkModerateUrl)"
    :selected-ids="selectedIds"
    @update:selected-ids="selectedIds = $event"
  />

  <Pagination :pagination="pagination" :base-path="routes.forumLatest" />
</template>
