<script setup lang="ts">
import { ref, computed } from 'vue'
import { Link, router } from '@inertiajs/vue3'
import { Head } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import Button from '@/components/ui/Button.vue'
import TopicListTable, { type TopicListItem } from '@/components/portal/TopicListTable.vue'
import Badge from '@/components/ui/Badge.vue'
import SubscriptionLevelSelect, { type SubscriptionLevelOption } from '@/components/portal/SubscriptionLevelSelect.vue'
import Select from '@/components/ui/Select.vue'
import BulkModerateToolbar from '@/components/portal/BulkModerateToolbar.vue'
import { routes } from '@/lib/routes'
import { appendQueryParams } from '@/lib/utils'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

export type TopicItem = TopicListItem

const props = defineProps<{
  section: {
    name: string
    slug: string
    description: string | null
    color_hex?: string | null
    icon?: string | null
    banner_text?: string | null
    link_url?: string | null
    link_label?: string | null
    read_only?: boolean
    notification_level?: 'watching' | 'tracking' | 'normal' | null
    new_topic_url: string | null
    watching: boolean
    muted?: boolean
    subscription_url: string
    mute_url?: string | null
    mark_all_read_url?: string | null
    rss_url: string
    required_tags?: Array<{ name: string; slug: string; url: string }>
    allowed_tags?: Array<{ name: string; slug: string; url: string }>
    prefix_required?: boolean
    moderators?: Array<{ username: string; url: string }>
  }
  featuredTopics: TopicItem[]
  topics: TopicItem[]
  pagination: PaginationMeta
  sort: string
  filter: string
  filterOptions: Array<{ value: string; label: string }>
  activeFilters?: Array<{ param: string; label: string; value?: string }>
  canCreateTopic: boolean
  canBulkModerate?: boolean
  bulkModerateUrl?: string | null
  subscriptionLevels?: SubscriptionLevelOption[]
  meta?: { title: string; description?: string | null }
}>()

const sortOptions = computed(() => [
  { value: 'activity', label: t('forum.latest.sortActivity') },
  { value: 'hot', label: t('forum.latest.sortHot') },
  { value: 'newest', label: t('forum.latest.sortNewest') },
  { value: 'replies', label: t('forum.latest.sortReplies') },
  { value: 'views', label: t('forum.latest.sortViews') },
])

function changeSort(value: string) {
  router.get(routes.forumSection(props.section.slug), { sort: value, filter: props.filter || undefined }, { preserveState: true })
}

function changeFilter(value: string) {
  router.get(routes.forumSection(props.section.slug), { sort: props.sort, filter: value || undefined }, { preserveState: true })
}

function removeFilter(chip: { param: string }) {
  router.get(routes.forumSection(props.section.slug), {
    sort: chip.param === 'sort' ? undefined : (props.sort === 'activity' ? undefined : props.sort),
    filter: chip.param === 'filter' ? undefined : (props.filter || undefined),
  }, { preserveState: true })
}

function toggleMute() {
  if (!props.section.mute_url) return
  router.post(appendQueryParams(props.section.mute_url, sectionListParams()), {}, { preserveScroll: true })
}
function sectionListParams() {
  return {
    sort: props.sort === 'activity' ? undefined : props.sort,
    filter: props.filter || undefined,
  }
}

function markAllRead() {
  if (!props.section.mark_all_read_url) return
  router.patch(appendQueryParams(props.section.mark_all_read_url, sectionListParams()))
}

const selectedIds = ref<string[]>([])

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
  <Head v-if="meta">
    <title>{{ meta.title }}</title>
    <meta v-if="meta.description" name="description" :content="meta.description" />
    <meta property="og:title" :content="meta.title" />
    <meta v-if="meta.description" property="og:description" :content="meta.description" />
  </Head>
  <Breadcrumb :items="[
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.forum'), href: routes.forum },
    { label: section.name, current: true },
  ]" />

  <div
    v-if="section.color_hex"
    class="mb-4 h-1 w-full max-w-xl rounded-full"
    :style="{ backgroundColor: section.color_hex }"
  />

  <div class="mb-6 flex flex-wrap items-start justify-between gap-4">
    <PageHeader
      :title="`${section.icon ? section.icon + ' ' : ''}${section.name}`"
      :subtitle="section.description || undefined"
    />
    <div class="flex flex-wrap gap-2">
      <SubscriptionLevelSelect
        v-if="subscriptionLevels?.length"
        :options="subscriptionLevels"
        :subscription-url="section.subscription_url"
        :watching="section.watching"
        :notification-level="section.notification_level"
      />
      <Button v-if="section.mute_url" type="button" variant="outline" size="sm" @click="toggleMute">
        {{ section.muted ? t('forum.sections.unmuteSection') : t('forum.sections.muteSection') }}
      </Button>
      <Button v-if="section.mark_all_read_url" type="button" variant="outline" size="sm" @click="markAllRead">
        {{ t('forum.sections.markAllRead') }}
      </Button>
      <BulkModerateToolbar
        v-if="canBulkModerate && bulkModerateUrl"
        :count="selectedIds.length"
        @moderate="bulkModerate"
      />
      <Button v-if="canCreateTopic && section.new_topic_url" as-child>
        <Link :href="section.new_topic_url">{{ t('forum.sections.newTopic') }}</Link>
      </Button>
      <Button as-child variant="outline" size="sm">
        <a :href="section.rss_url" target="_blank" rel="noopener">RSS</a>
      </Button>
    </div>
  </div>

  <p v-if="section.banner_text" class="mb-4 rounded-md border border-sky-200 bg-sky-50 px-3 py-2 text-sm text-sky-900 dark:border-sky-900 dark:bg-sky-950 dark:text-sky-100">
    {{ section.banner_text }}
  </p>

  <p v-if="section.moderators?.length" class="mb-4 text-sm text-muted-foreground">
    {{ t('forum.sections.moderators') }}
    <template v-for="(mod, index) in section.moderators" :key="mod.username">
      <Link :href="mod.url" class="text-primary hover:underline">{{ mod.username }}</Link><span v-if="index < section.moderators.length - 1">{{ t('common.listSeparator') }}</span>
    </template>
  </p>

  <p v-if="section.link_url" class="mb-4 text-sm">
    <a :href="section.link_url" class="font-medium text-primary underline" target="_blank" rel="noopener noreferrer">
      {{ section.link_label || section.link_url }}
    </a>
  </p>

  <p v-if="section.read_only" class="mb-4 rounded-md border border-slate-300 bg-slate-50 px-3 py-2 text-sm text-slate-800 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-100">
    {{ t('forum.sections.readOnlyNotice') }}
  </p>

  <p v-if="section.required_tags?.length" class="mb-4 rounded-md border border-amber-200 bg-amber-50 px-3 py-2 text-sm text-amber-900 dark:border-amber-900 dark:bg-amber-950 dark:text-amber-100">
    {{ t('forum.sections.requiredTags') }}
    <template v-for="(tag, index) in section.required_tags" :key="tag.slug">
      <Link :href="tag.url" class="font-medium underline">{{ tag.name }}</Link><span v-if="index < section.required_tags.length - 1">{{ t('common.listSeparator') }}</span>
    </template>
  </p>
  <p v-if="section.allowed_tags?.length" class="mb-4 rounded-md border border-blue-200 bg-blue-50 px-3 py-2 text-sm text-blue-900 dark:border-blue-900 dark:bg-blue-950 dark:text-blue-100">
    {{ t('forum.sections.allowedTags') }}
    <template v-for="(tag, index) in section.allowed_tags" :key="`allowed-${tag.slug}`">
      <Link :href="tag.url" class="font-medium underline">{{ tag.name }}</Link><span v-if="index < section.allowed_tags.length - 1">{{ t('common.listSeparator') }}</span>
    </template>
  </p>
  <p v-if="section.prefix_required" class="mb-4 rounded-md border border-violet-200 bg-violet-50 px-3 py-2 text-sm text-violet-900">
    {{ t('forum.sections.prefixRequired') }}
  </p>

  <div class="mb-4 flex flex-wrap items-center gap-4">
    <div class="flex items-center gap-2">
      <label class="text-sm text-muted-foreground">{{ t('forum.lists.sortLabel') }}</label>
      <Select
        :model-value="sort"
        :options="sortOptions"
        size="sm"
        @update:model-value="changeSort"
      />
    </div>
    <div class="flex items-center gap-2">
      <label class="text-sm text-muted-foreground">{{ t('forum.lists.filterLabel') }}</label>
      <Select
        :model-value="filter"
        :options="filterOptions"
        size="sm"
        @update:model-value="changeFilter"
      />
    </div>
  </div>

  <div v-if="activeFilters?.length" class="mb-4 flex flex-wrap items-center gap-2">
    <span class="text-xs text-muted-foreground">{{ t('forum.lists.activeFilters') }}</span>
    <span
      v-for="chip in activeFilters"
      :key="`${chip.param}-${chip.value || chip.label}`"
      class="inline-flex items-center gap-1 rounded-full border border-primary/30 bg-primary/5 px-2.5 py-0.5 text-xs text-primary"
    >
      {{ chip.label }}
      <button type="button" class="hover:opacity-70" :title="t('forum.lists.removeFilter')" @click="removeFilter(chip)">×</button>
    </span>
  </div>

  <div v-if="featuredTopics.length" class="mb-6">
    <h2 class="mb-2 text-sm font-semibold">{{ t('forum.sections.featuredTopics') }}</h2>
    <div class="space-y-2 rounded-lg border p-3">
      <div v-for="topic in featuredTopics" :key="topic.id" class="flex items-center gap-2 text-sm">
        <Badge variant="secondary">{{ t('forum.sections.featuredBadge') }}</Badge>
        <Link :href="topic.url" class="font-medium hover:underline">{{ topic.title }}</Link>
      </div>
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

  <Pagination :pagination="pagination" :base-path="routes.forumSection(section.slug)" />
</template>
