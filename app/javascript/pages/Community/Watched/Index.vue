<script setup lang="ts">
import { router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import TopicListTable, { type TopicListItem } from '@/components/portal/TopicListTable.vue'
import ListFilterBar from '@/components/portal/ListFilterBar.vue'
import Select from '@/components/ui/Select.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

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
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.forum'), href: routes.forum },
    { label: t('forum.watched.topicsBreadcrumb'), current: true },
  ]" />

  <PageHeader :title="t('forum.watched.topicsTitle')" :subtitle="t('forum.watched.topicsSubtitle')" />

  <ListFilterBar>
    <div class="flex items-center gap-2">
      <label class="text-sm text-muted-foreground">{{ t('forum.lists.sortLabel') }}</label>
      <Select :model-value="sort" :options="sortOptions" size="sm" @update:model-value="changeSort" />
    </div>
  </ListFilterBar>

  <TopicListTable :topics="topics" show-views />

  <Pagination :pagination="pagination" :base-path="routes.forumWatching" />
</template>
