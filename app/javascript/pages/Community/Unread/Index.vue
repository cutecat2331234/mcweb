<script setup lang="ts">
import { computed, ref } from 'vue'
import { Link, router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import TopicListTable, { type TopicListItem } from '@/components/portal/TopicListTable.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Select from '@/components/ui/Select.vue'
import { routes } from '@/lib/routes'
import { appendQueryParams } from '@/lib/utils'
import { readCsrfToken } from '@/lib/csrf'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

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
  filterBookmarkUrl?: string | null
  savedFilterPresets?: Array<{ id: number; name: string; url: string; delete_url: string }>
  saveFilterPresetUrl?: string
  activeFilters?: Array<{ param: string; label: string; value?: string }>
}>()

const selectedIds = ref<string[]>([])
const bookmarkCopied = ref(false)
const saveName = ref('')
const saving = ref(false)
const saveError = ref('')

const tagPicker = ref('')

const availableTagOptions = computed(() => [
  { value: '', label: t('forum.lists.addTagFilter') },
  ...props.tagOptions
    .filter((o) => o.value && !selectedTagSlugs.value.includes(o.value))
    .map((o) => ({ value: o.value, label: o.label })),
])

function onPickTag(value: string) {
  if (value) addTag(value)
  tagPicker.value = ''
}

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
  router.patch(appendQueryParams(props.markAllReadUrl, listParams()))
}

function markSelectedRead() {
  if (!props.markSelectedReadUrl || selectedIds.value.length === 0) return
  router.patch(
    appendQueryParams(props.markSelectedReadUrl, listParams()),
    { topic_ids: selectedIds.value },
    { onSuccess: () => { selectedIds.value = [] } },
  )
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

function hasActiveFilters() {
  return !!(
    (props.sort && props.sort !== 'latest')
    || props.filter
    || props.section
    || selectedTagSlugs.value.length
    || (selectedTagSlugs.value.length > 1 && props.tagMatch === 'any')
  )
}

async function copyFilterBookmark() {
  if (!props.filterBookmarkUrl) return
  try {
    await navigator.clipboard.writeText(props.filterBookmarkUrl)
    bookmarkCopied.value = true
    window.setTimeout(() => { bookmarkCopied.value = false }, 2000)
  } catch {
    // ignore clipboard errors
  }
}

async function saveFilterPreset() {
  if (!props.saveFilterPresetUrl || !saveName.value.trim()) return
  saving.value = true
  saveError.value = ''
  try {
    const token = readCsrfToken()
    const response = await fetch(props.saveFilterPresetUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
        'X-CSRF-Token': token,
      },
      credentials: 'same-origin',
      body: JSON.stringify({
        unread_filter_preset: {
          name: saveName.value.trim(),
          filters: {
            sort: props.sort,
            filter: props.filter,
            section: props.section,
            tags: selectedTagSlugs.value.join(','),
            tag_match: props.tagMatch,
          },
        },
      }),
    })
    if (!response.ok) {
      const data = await response.json().catch(() => ({}))
      saveError.value = data.error || t('forum.lists.saveFailed')
      return
    }
    saveName.value = ''
    router.reload({ only: ['savedFilterPresets'] })
  } finally {
    saving.value = false
  }
}

async function deleteFilterPreset(deleteUrl: string) {
  const token = readCsrfToken()
  await fetch(deleteUrl, {
    method: 'DELETE',
    headers: { 'X-CSRF-Token': token, Accept: 'application/json' },
    credentials: 'same-origin',
  })
  router.reload({ only: ['savedFilterPresets'] })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.forum'), href: routes.forum },
    { label: t('forum.unread.breadcrumb'), current: true },
  ]" />

  <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
    <PageHeader :title="t('forum.unread.title')" :subtitle="t('forum.unread.subtitle')" />
    <div class="flex flex-wrap items-center gap-2">
      <Select :model-value="sort" :options="sortOptions" size="sm" @update:model-value="changeSort" />
      <Select :model-value="filter" :options="filterOptions" size="sm" @update:model-value="changeFilter" />
      <Select :model-value="section" :options="sectionOptions" size="sm" @update:model-value="changeSection" />
      <Select v-model="tagPicker" :options="availableTagOptions" size="sm" @update:model-value="onPickTag" />
      <Select
        v-if="selectedTagSlugs.length > 1"
        :model-value="tagMatch"
        :options="tagMatchOptions"
        size="sm"
        @update:model-value="changeTagMatch"
      />
      <Button
        v-if="markSelectedReadUrl && selectedIds.length"
        type="button"
        variant="outline"
        size="sm"
        @click="markSelectedRead"
      >
        {{ t('forum.lists.markSelectedRead', { count: selectedIds.length }) }}
      </Button>
      <Button v-if="topics.length" type="button" variant="outline" size="sm" @click="markAllRead">
        {{ t('forum.lists.markAllRead') }}
      </Button>
    </div>
  </div>

  <div v-if="saveFilterPresetUrl && hasActiveFilters()" class="mb-4 flex flex-wrap items-end gap-2 rounded-lg border p-3">
    <div class="space-y-1">
      <label class="text-sm font-medium">{{ t('forum.lists.saveCurrentFilter') }}</label>
      <Input v-model="saveName" :placeholder="t('forum.lists.filterNamePlaceholder')" class="w-48" />
    </div>
    <Button type="button" variant="outline" size="sm" :disabled="saving || !saveName.trim()" @click="saveFilterPreset">
      {{ saving ? t('forum.lists.saving') : t('forum.lists.saveFilter') }}
    </Button>
    <p v-if="saveError" class="text-sm text-destructive">{{ saveError }}</p>
  </div>

  <div v-if="savedFilterPresets?.length" class="mb-4 flex flex-wrap gap-2">
    <span class="text-sm text-muted-foreground">{{ t('forum.lists.savedFilters') }}</span>
    <span v-for="preset in savedFilterPresets" :key="preset.id" class="inline-flex items-center gap-1 rounded-full border px-3 py-1 text-sm">
      <Link :href="preset.url" class="hover:underline">{{ preset.name }}</Link>
      <button type="button" class="text-muted-foreground hover:text-destructive" @click="deleteFilterPreset(preset.delete_url)">×</button>
    </span>
  </div>

  <div v-if="activeFilters?.length" class="mb-4 flex flex-wrap items-center gap-2">
    <span class="text-xs text-muted-foreground">{{ t('forum.lists.activeFilters') }}</span>
    <Button
      v-if="filterBookmarkUrl"
      type="button"
      variant="outline"
      size="sm"
      @click="copyFilterBookmark"
    >
      {{ bookmarkCopied ? t('forum.lists.linkCopied') : t('forum.lists.copyFilterLink') }}
    </Button>
    <span
      v-for="chip in activeFilters"
      :key="`${chip.param}-${chip.value || chip.label}`"
      class="inline-flex items-center gap-1 rounded-full border border-primary/30 bg-primary/5 px-2.5 py-0.5 text-xs text-primary"
    >
      {{ chip.label }}
      <button type="button" class="hover:opacity-70" :title="t('forum.lists.removeFilter')" @click="removeFilter(chip)">×</button>
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
