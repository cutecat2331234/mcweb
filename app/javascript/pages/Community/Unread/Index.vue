<script setup lang="ts">
import { computed, ref } from 'vue'
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
  markSelectedReadUrl?: string
  pagination: PaginationMeta
  sort: string
  filter: string
  section: string
  tags: string
  tagMatch: string
  tagMatchOptions: Array<{ value: string; label: string }>
  sortOptions: Array<{ value: string; label: string }>
  filterOptions: Array<{ value: string; label: string }>
  sectionOptions: Array<{ value: string; label: string }>
  tagOptions: Array<{ value: string; label: string }>
  activeFilters?: Array<{ param: string; label: string; value?: string }>
}>()

const selectedIds = ref<string[]>([])

const selectedTagSlugs = computed(() =>
  props.tags
    ? props.tags.split(',').map((slug) => slug.trim()).filter(Boolean)
    : [],
)

function listParams(overrides: Record<string, string | undefined> = {}) {
  const tagsValue = overrides.tags ?? (selectedTagSlugs.value.length ? selectedTagSlugs.value.join(',') : undefined)
  const tagMatchValue = overrides.tag_match ?? (props.tagMatch === 'all' ? undefined : props.tagMatch)
  return {
    sort: overrides.sort ?? (props.sort === 'latest' ? undefined : props.sort),
    filter: overrides.filter ?? (props.filter || undefined),
    section: overrides.section ?? (props.section || undefined),
    tags: tagsValue,
    tag_match: tagMatchValue,
  }
}

function markAllRead() {
  router.patch(props.markAllReadUrl)
}

function markSelectedRead() {
  if (!props.markSelectedReadUrl || selectedIds.value.length === 0) return
  router.patch(props.markSelectedReadUrl, { topic_ids: selectedIds.value }, {
    onSuccess: () => { selectedIds.value = [] },
  })
}

function changeSort(value: string) {
  router.get(routes.forumUnread, listParams({ sort: value || undefined }), { preserveState: true })
}

function changeFilter(value: string) {
  router.get(routes.forumUnread, listParams({ filter: value || undefined }), { preserveState: true })
}

function changeSection(value: string) {
  router.get(routes.forumUnread, listParams({ section: value || undefined }), { preserveState: true })
}

function addTag(value: string) {
  if (!value) return
  const next = selectedTagSlugs.value.includes(value)
    ? selectedTagSlugs.value
    : [ ...selectedTagSlugs.value, value ]
  router.get(routes.forumUnread, listParams({ tags: next.join(',') }), { preserveState: true })
}

function changeTagMatch(value: string) {
  router.get(routes.forumUnread, listParams({ tag_match: value === 'all' ? undefined : value }), { preserveState: true })
}

function removeFilter(chip: { param: string; value?: string }) {
  const overrides: Record<string, string | undefined> = {}
  if (chip.param === 'sort') overrides.sort = undefined
  if (chip.param === 'filter') overrides.filter = undefined
  if (chip.param === 'section') overrides.section = undefined
  if (chip.param === 'tag_match') overrides.tag_match = undefined
  if (chip.param === 'tags' && chip.value) {
    const next = selectedTagSlugs.value.filter((slug) => slug !== chip.value)
    overrides.tags = next.length ? next.join(',') : undefined
  }
  router.get(routes.forumUnread, listParams(overrides), { preserveState: true })
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
      <select
        :value="filter"
        class="h-8 rounded-md border border-input bg-transparent px-2 text-sm"
        @change="changeFilter(($event.target as HTMLSelectElement).value)"
      >
        <option v-for="opt in filterOptions" :key="opt.value" :value="opt.value">{{ opt.label }}</option>
      </select>
      <select
        :value="section"
        class="h-8 rounded-md border border-input bg-transparent px-2 text-sm"
        @change="changeSection(($event.target as HTMLSelectElement).value)"
      >
        <option v-for="opt in sectionOptions" :key="opt.value" :value="opt.value">{{ opt.label }}</option>
      </select>
      <select
        class="h-8 rounded-md border border-input bg-transparent px-2 text-sm"
        @change="addTag(($event.target as HTMLSelectElement).value); ($event.target as HTMLSelectElement).value = ''"
      >
        <option value="">添加标签筛选…</option>
        <option
          v-for="opt in tagOptions.filter((o) => o.value && !selectedTagSlugs.includes(o.value))"
          :key="opt.value"
          :value="opt.value"
        >
          {{ opt.label }}
        </option>
      </select>
      <select
        v-if="selectedTagSlugs.length > 1"
        :value="tagMatch"
        class="h-8 rounded-md border border-input bg-transparent px-2 text-sm"
        @change="changeTagMatch(($event.target as HTMLSelectElement).value)"
      >
        <option v-for="opt in tagMatchOptions" :key="opt.value" :value="opt.value">{{ opt.label }}</option>
      </select>
      <Button
        v-if="markSelectedReadUrl && selectedIds.length"
        type="button"
        variant="outline"
        size="sm"
        @click="markSelectedRead"
      >
        标选中为已读（{{ selectedIds.length }}）
      </Button>
      <Button v-if="topics.length" type="button" variant="outline" size="sm" @click="markAllRead">
        全部标为已读
      </Button>
    </div>
  </div>

  <div v-if="activeFilters?.length" class="mb-4 flex flex-wrap items-center gap-2">
    <span class="text-xs text-muted-foreground">已选筛选：</span>
    <span
      v-for="chip in activeFilters"
      :key="`${chip.param}-${chip.value || chip.label}`"
      class="inline-flex items-center gap-1 rounded-full border border-primary/30 bg-primary/5 px-2.5 py-0.5 text-xs text-primary"
    >
      {{ chip.label }}
      <button type="button" class="hover:opacity-70" title="移除此筛选" @click="removeFilter(chip)">×</button>
    </span>
  </div>

  <TopicListTable
    :topics="topics"
    show-views
    selectable
    :selected-ids="selectedIds"
    @update:selected-ids="selectedIds = $event"
  />

  <Pagination v-if="pagination.pages > 1" :pagination="pagination" :base-path="routes.forumUnread" />
</template>
