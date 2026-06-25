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
import Button from '@/components/ui/Button.vue'
import Select from '@/components/ui/Select.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

const props = defineProps<{
  topics: TopicListItem[]
  pagination: PaginationMeta
  period: string
  periodOptions: Array<{ value: string; label: string }>
  filter: string
  filterOptions: Array<{ value: string; label: string }>
  activeFilters?: Array<{ param: string; label: string; value?: string }>
  rss_url: string
  canBulkModerate?: boolean
  bulkModerateUrl?: string | null
}>()

const selectedIds = ref<string[]>([])

function changePeriod(value: string) {
  router.get(routes.forumTop, { period: value, filter: props.filter || undefined }, { preserveState: true })
}

function changeFilter(value: string) {
  router.get(routes.forumTop, { period: props.period, filter: value || undefined }, { preserveState: true })
}

function removeFilter() {
  router.get(routes.forumTop, { period: props.period }, { preserveState: true })
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
    { label: t('forum.top.breadcrumb'), current: true },
  ]" />

  <PageHeader :title="t('forum.top.title')" :subtitle="t('forum.top.subtitle')" />

  <div class="mb-4 flex flex-wrap items-center gap-4">
    <div class="flex items-center gap-2">
      <label class="text-sm text-muted-foreground">{{ t('forum.top.periodLabel') }}</label>
      <div class="flex flex-wrap gap-1">
        <Button
          v-for="option in periodOptions"
          :key="option.value"
          :variant="period === option.value ? 'default' : 'outline'"
          size="sm"
          @click="changePeriod(option.value)"
        >
          {{ option.label }}
        </Button>
      </div>
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
    <a :href="rss_url" target="_blank" rel="noopener" class="text-sm text-muted-foreground hover:text-foreground">{{ t('forum.lists.rss') }}</a>
  </div>

  <div v-if="activeFilters?.length" class="mb-4 flex flex-wrap items-center gap-2">
    <span class="text-xs text-muted-foreground">{{ t('forum.lists.activeFilters') }}</span>
    <span
      v-for="chip in activeFilters"
      :key="`${chip.param}-${chip.value || chip.label}`"
      class="inline-flex items-center gap-1 rounded-full border border-primary/30 bg-primary/5 px-2.5 py-0.5 text-xs text-primary"
    >
      {{ chip.label }}
      <button type="button" class="hover:opacity-70" :title="t('forum.lists.removeFilter')" @click="removeFilter">×</button>
    </span>
  </div>

  <TopicListTable
    v-if="topics.length"
    :topics="topics"
    show-views
    :selectable="!!(canBulkModerate && bulkModerateUrl)"
    :selected-ids="selectedIds"
    @update:selected-ids="selectedIds = $event"
  />
  <p v-else class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">{{ t('forum.top.empty') }}</p>

  <Pagination :pagination="pagination" :base-path="routes.forumTop" />
</template>
