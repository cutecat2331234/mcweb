<script setup lang="ts">
import { computed } from 'vue'
import { Link, router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import TopicListTable, { type TopicListItem } from '@/components/portal/TopicListTable.vue'
import SubscriptionLevelSelect, { type SubscriptionLevelOption } from '@/components/portal/SubscriptionLevelSelect.vue'
import ListFilterBar from '@/components/portal/ListFilterBar.vue'
import Select from '@/components/ui/Select.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

const props = defineProps<{
  tag: {
    name: string
    slug: string
    description?: string | null
    color_hex?: string | null
    rss_url: string
    watching?: boolean
    notification_level?: 'watching' | 'tracking' | 'normal' | null
    subscription_url?: string
  }
  topics: TopicListItem[]
  pagination: PaginationMeta
  loggedIn?: boolean
  sort?: string
  subscriptionLevels?: SubscriptionLevelOption[]
}>()

const sortOptions = computed(() => [
  { value: 'activity', label: t('forum.latest.sortActivity') },
  { value: 'hot', label: t('forum.latest.sortHot') },
  { value: 'newest', label: t('forum.latest.sortNewest') },
  { value: 'replies', label: t('forum.latest.sortReplies') },
  { value: 'views', label: t('forum.latest.sortViews') },
])

function changeSort(value: string) {
  router.get(`/app/forum/tags/${props.tag.slug}`, { sort: value }, { preserveState: true })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.forum'), href: routes.forum },
    { label: t('forum.tags.tagBreadcrumb', { name: tag.name }), current: true },
  ]" />

  <div v-if="tag.color_hex" class="mb-4 h-1 w-full max-w-xl rounded-full" :style="{ backgroundColor: tag.color_hex }" />

  <div class="mb-4 flex flex-wrap items-start justify-between gap-3">
    <PageHeader :title="`#${tag.name}`" :subtitle="t('forum.tags.browseSubtitle')" />
    <SubscriptionLevelSelect
      v-if="loggedIn && tag.subscription_url && subscriptionLevels?.length"
      :options="subscriptionLevels"
      :subscription-url="tag.subscription_url"
      :watching="!!tag.watching"
      :notification-level="tag.notification_level"
    />
  </div>

  <p v-if="tag.description" class="mb-4 text-sm text-muted-foreground">{{ tag.description }}</p>

  <p class="mb-4">
    <a :href="tag.rss_url" target="_blank" rel="noopener" class="text-sm text-muted-foreground hover:text-foreground">{{ t('forum.tags.rss') }}</a>
  </p>

  <ListFilterBar>
    <div class="flex items-center gap-2">
      <label class="text-sm text-muted-foreground">{{ t('forum.lists.sortLabel') }}</label>
      <Select
        :model-value="sort || 'activity'"
        :options="sortOptions"
        size="sm"
        @update:model-value="changeSort"
      />
    </div>
  </ListFilterBar>

  <TopicListTable :topics="topics" show-views />

  <Pagination :pagination="pagination" :base-path="`/app/forum/tags/${tag.slug}`" />
</template>
