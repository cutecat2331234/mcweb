<script setup lang="ts">
import { router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import TopicListTable, { type TopicListItem } from '@/components/portal/TopicListTable.vue'
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
  router.get(routes.forumWatchedTagTopics, { sort: value }, { preserveState: true })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.forum'), href: routes.forum },
    { label: t('forum.watched.tagsBreadcrumb'), href: routes.forumWatchedTags },
    { label: t('forum.watched.tagTopicsBreadcrumb'), current: true },
  ]" />

  <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
    <PageHeader :title="t('forum.watched.tagTopicsPageTitle')" :subtitle="t('forum.watched.tagTopicsPageSubtitle')" />
    <Select :model-value="sort" :options="sortOptions" size="sm" @update:model-value="changeSort" />
  </div>

  <TopicListTable :topics="topics" show-views show-participants />

  <p v-if="!topics.length" class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
    {{ t('forum.watched.emptyTagTopics') }}
  </p>

  <Pagination v-if="pagination.pages > 1" :pagination="pagination" :base-path="routes.forumWatchedTagTopics" />
</template>
