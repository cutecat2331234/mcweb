<script setup lang="ts">
import { ref } from 'vue'
import { Link, router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Badge from '@/components/ui/Badge.vue'
import { routes } from '@/lib/routes'
import { appendQueryParams } from '@/lib/utils'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

export interface NotificationGroup {
  key: string
  notification_type: string
  category: 'forum' | 'commerce'
  title: string
  body: string | null
  count: number
  unread_count: number
  read: boolean
  latest_at: string
  visit_url: string | null
  items: Array<{
    id: number
    title: string
    body: string | null
    created_at: string
    visit_url: string
    mark_read_url: string
    read: boolean
    category: 'forum' | 'commerce'
    auto_dismiss?: boolean
  }>
}

interface TimelineSection {
  key: string
  label: string
  count: number
  groups: NotificationGroup[]
  default_expanded: boolean
}

interface NotificationSection {
  key: string
  label: string
  count: number
  groups: NotificationGroup[]
  timeline_sections?: TimelineSection[]
  default_expanded: boolean
}

interface TypeTab {
  type: string
  label: string
  href: string
  active: boolean
  count: number
  unread_count?: number
}

interface QuickFilter {
  key: string
  label: string
  type: string
  href: string
  active: boolean
  count: number
  unread_count?: number
}

interface PeriodFilter {
  key: string
  label: string
  period: string
  href: string
  active: boolean
  count: number
}

const props = defineProps<{
  notifications: NotificationGroup[]
  notificationSections?: NotificationSection[]
  activeCategory: 'all' | 'forum' | 'commerce'
  activeRead?: 'all' | 'unread'
  activeType?: string
  activePeriod?: string
  typeTabs?: TypeTab[]
  quickFilters?: QuickFilter[]
  periodFilters?: PeriodFilter[]
  activeFilters?: Array<{ param: string; label: string; value?: string }>
  unreadCount?: number
}>()

const expanded = ref<Record<string, boolean>>({})
const sectionExpanded = ref<Record<string, boolean>>({})
const timelineExpanded = ref<Record<string, boolean>>({})

function isTimelineExpanded(sectionKey: string, timeline: TimelineSection) {
  const key = `${sectionKey}-${timeline.key}`
  if (timelineExpanded.value[key] != null) {
    return timelineExpanded.value[key]
  }
  return timeline.default_expanded
}

function toggleTimeline(sectionKey: string, timeline: TimelineSection) {
  const key = `${sectionKey}-${timeline.key}`
  const current = timelineExpanded.value[key] ?? timeline.default_expanded
  timelineExpanded.value[key] = !current
}

function isSectionExpanded(section: NotificationSection) {
  if (sectionExpanded.value[section.key] != null) {
    return sectionExpanded.value[section.key]
  }
  return section.default_expanded
}

function toggleSection(key: string, defaultExpanded: boolean) {
  const current = sectionExpanded.value[key] ?? defaultExpanded
  sectionExpanded.value[key] = !current
}

function filterParams(overrides: Record<string, string | undefined> = {}) {
  const category = overrides.category ?? (props.activeCategory === 'all' ? undefined : props.activeCategory)
  const read = overrides.read ?? (props.activeRead === 'unread' ? 'unread' : undefined)
  const type = overrides.type ?? (props.activeType || undefined)
  const period = overrides.period ?? (props.activePeriod || undefined)
  return { category, read, type, period }
}

function markAllRead() {
  router.patch(appendQueryParams(`${routes.app}/forum/notifications/mark_all_read`, filterParams()))
}

function dismissAlerts() {
  router.patch(`${routes.app}/forum/notifications/dismiss_alerts`)
}

function switchRead(read: 'all' | 'unread') {
  router.get(routes.forumNotifications, filterParams({ read: read === 'unread' ? 'unread' : undefined }), { preserveState: true })
}

function toggleExpand(key: string) {
  expanded.value[key] = !expanded.value[key]
}

function markRead(url: string) {
  router.patch(appendQueryParams(url, filterParams()), {}, { preserveScroll: true })
}

function switchCategory(category: 'all' | 'forum' | 'commerce') {
  router.get(routes.forumNotifications, filterParams({ category: category === 'all' ? undefined : category, type: undefined }), { preserveState: true })
}

function removeFilter(filter: { param: string }) {
  const overrides: Record<string, string | undefined> = {}
  if (filter.param === 'category') overrides.category = undefined
  if (filter.param === 'read') overrides.read = undefined
  if (filter.param === 'period') overrides.period = undefined
  if (filter.param === 'type') overrides.type = undefined
  router.get(routes.forumNotifications, filterParams(overrides), { preserveState: true })
}

function clearAllFilters() {
  router.get(routes.forumNotifications, {}, { preserveState: true })
}

function categoryLabel(category: string) {
  return category === 'commerce' ? t('community.notifications.store') : t('community.notifications.forum')
}

const displaySections = () => {
  if (props.notificationSections?.length) return props.notificationSections
  if (!props.notifications.length) return []
  return [{
    key: 'all',
    label: t('community.notifications.all'),
    count: props.notifications.length,
    groups: props.notifications,
    timeline_sections: [],
    default_expanded: true,
  }]
}

function sectionTimelines(section: NotificationSection): TimelineSection[] {
  if (section.timeline_sections?.length) return section.timeline_sections
  if (!section.groups.length) return []
  return [{
    key: 'all',
    label: t('community.notifications.all'),
    count: section.groups.length,
    groups: section.groups,
    default_expanded: true,
  }]
}
</script>

<template>
  <Breadcrumb :items="[
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.forum'), href: routes.forum },
    { label: t('community.notifications.title'), current: true },
  ]" />

  <PageHeader :title="t('community.notifications.title')" :subtitle="t('community.notifications.subtitle')">
    <template #actions>
      <Button type="button" variant="outline" size="sm" @click="markAllRead">
        {{ t('community.notifications.markAllRead') }}
      </Button>
      <Button type="button" variant="outline" size="sm" @click="dismissAlerts">
        {{ t('community.notifications.dismissAlerts') }}
      </Button>
    </template>
  </PageHeader>

  <div class="mb-6 space-y-3 rounded-xl bg-muted/30 p-3 sm:p-4">
    <div class="-mx-1 flex flex-nowrap items-center gap-2 overflow-x-auto px-1 pb-1 [scrollbar-width:thin] sm:flex-wrap">
      <Button :variant="activeCategory === 'all' ? 'default' : 'ghost'" size="sm" class="shrink-0" @click="switchCategory('all')">{{ t('community.notifications.all') }}</Button>
      <Button :variant="activeCategory === 'forum' ? 'default' : 'ghost'" size="sm" class="shrink-0" @click="switchCategory('forum')">{{ t('community.notifications.forum') }}</Button>
      <Button :variant="activeCategory === 'commerce' ? 'default' : 'ghost'" size="sm" class="shrink-0" @click="switchCategory('commerce')">{{ t('community.notifications.store') }}</Button>
      <span class="mx-1 h-5 w-px shrink-0 bg-border" aria-hidden="true" />
      <Button :variant="(activeRead || 'all') === 'all' ? 'default' : 'ghost'" size="sm" class="shrink-0" @click="switchRead('all')">{{ t('community.notifications.allMessages') }}</Button>
      <Button :variant="activeRead === 'unread' ? 'default' : 'ghost'" size="sm" class="shrink-0" @click="switchRead('unread')">
        {{ t('community.notifications.unread') }}<span v-if="unreadCount != null && unreadCount > 0"> ({{ unreadCount }})</span>
      </Button>
    </div>

    <div v-if="periodFilters?.length" class="-mx-1 flex flex-nowrap items-center gap-2 overflow-x-auto px-1 pb-1 [scrollbar-width:thin] sm:flex-wrap">
      <span class="shrink-0 text-xs font-medium text-muted-foreground">{{ t('community.notifications.timeFilter') }}</span>
      <Link
        v-for="pf in periodFilters"
        :key="pf.key"
        :href="pf.href"
        class="shrink-0 rounded-md px-2.5 py-1 text-xs no-underline transition-colors"
        :class="pf.active ? 'bg-primary text-primary-foreground shadow-sm' : 'text-muted-foreground hover:bg-background hover:text-foreground'"
      >
        {{ pf.label }}<span class="ml-1 opacity-80">({{ pf.count }})</span>
      </Link>
    </div>

    <div v-if="quickFilters?.length" class="-mx-1 flex flex-nowrap items-center gap-2 overflow-x-auto px-1 pb-1 [scrollbar-width:thin] sm:flex-wrap">
      <span class="shrink-0 text-xs font-medium text-muted-foreground">{{ t('community.notifications.quickFilter') }}</span>
      <Link
        v-for="qf in quickFilters"
        :key="qf.key"
        :href="qf.href"
        class="shrink-0 rounded-md px-2.5 py-1 text-xs no-underline transition-colors"
        :class="qf.active ? 'bg-primary text-primary-foreground shadow-sm' : 'text-muted-foreground hover:bg-background hover:text-foreground'"
      >
        {{ qf.label }}<span class="ml-1 opacity-80">({{ qf.count }})</span>
        <span v-if="qf.unread_count" class="ml-1 font-semibold">· {{ t('community.notifications.unreadCount', { count: qf.unread_count }) }}</span>
      </Link>
    </div>

    <div v-if="typeTabs?.length" class="-mx-1 flex flex-nowrap gap-2 overflow-x-auto px-1 pb-1 [scrollbar-width:thin] sm:flex-wrap">
      <Link
        v-for="tab in typeTabs"
        :key="tab.type"
        :href="tab.href"
        class="shrink-0 rounded-md px-2.5 py-1 text-xs no-underline transition-colors"
        :class="[
          tab.active ? 'bg-primary text-primary-foreground shadow-sm' : 'text-muted-foreground hover:bg-background hover:text-foreground',
          tab.unread_count ? 'font-semibold' : '',
        ]"
      >
        {{ tab.label }}<span class="ml-1 opacity-80">({{ tab.count }})</span>
        <span v-if="tab.unread_count" :class="tab.active ? 'ml-1' : 'ml-1 text-orange-600 dark:text-orange-400'">{{ t('community.notifications.unreadCount', { count: tab.unread_count }) }}</span>
      </Link>
    </div>

    <div v-if="activeFilters?.length" class="flex flex-wrap items-center gap-2 pt-1">
      <span class="text-xs font-medium text-muted-foreground">{{ t('community.notifications.activeFilters') }}</span>
      <span
        v-for="filter in activeFilters"
        :key="`${filter.param}-${filter.value || filter.label}`"
        class="inline-flex items-center gap-1 rounded-full bg-primary/10 px-2.5 py-1 text-xs text-primary"
      >
        {{ filter.label }}
        <button type="button" class="rounded-full px-0.5 hover:bg-primary/10 hover:opacity-80 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring" :title="t('community.notifications.removeFilter')" @click="removeFilter(filter)">×</button>
      </span>
      <Button type="button" variant="ghost" size="sm" class="h-7 text-xs" @click="clearAllFilters">{{ t('community.notifications.clearAll') }}</Button>
    </div>
  </div>

  <div v-if="displaySections().length" class="space-y-4">
    <section v-for="section in displaySections()" :key="section.key" class="overflow-hidden rounded-xl border bg-card/50">
      <button
        type="button"
        class="flex w-full items-center justify-between gap-3 px-4 py-3.5 text-left text-sm font-medium transition-colors hover:bg-muted/40 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring"
        :aria-expanded="isSectionExpanded(section)"
        @click="toggleSection(section.key, section.default_expanded)"
      >
        <span>{{ section.label }} ({{ section.count }})</span>
        <span class="text-xs text-muted-foreground">{{ isSectionExpanded(section) ? t('community.notifications.collapse') : t('community.notifications.expand') }}</span>
      </button>
      <div v-if="isSectionExpanded(section)" class="space-y-3 border-t p-3 sm:p-4">
        <div v-for="timeline in sectionTimelines(section)" :key="`${section.key}-${timeline.key}`" class="overflow-hidden rounded-lg bg-muted/35">
          <button
            type="button"
            class="flex w-full items-center justify-between gap-3 px-3 py-2.5 text-left text-xs font-medium text-muted-foreground transition-colors hover:bg-muted/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring"
            :aria-expanded="isTimelineExpanded(section.key, timeline)"
            @click="toggleTimeline(section.key, timeline)"
          >
            <span>{{ timeline.label }} ({{ timeline.count }})</span>
            <span>{{ isTimelineExpanded(section.key, timeline) ? t('community.notifications.collapse') : t('community.notifications.expand') }}</span>
          </button>
          <div v-if="isTimelineExpanded(section.key, timeline)" class="space-y-2 px-2 pb-2">
            <article
              v-for="group in timeline.groups"
              :key="group.key"
              class="rounded-md border-l-2 border-l-transparent bg-background/90 p-3 shadow-sm sm:p-4"
              :class="group.read ? 'opacity-75' : 'border-l-primary bg-primary/5'"
            >
              <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                <div class="min-w-0 flex-1">
                  <div class="flex flex-wrap items-center gap-2">
                    <Badge variant="outline" class="text-[10px]">{{ categoryLabel(group.category) }}</Badge>
                    <h3 class="min-w-0 text-sm font-medium leading-relaxed">{{ group.title }}</h3>
                    <Badge v-if="group.count > 1">{{ group.count }}</Badge>
                    <Badge v-if="group.unread_count" variant="default">{{ t('community.notifications.unreadCount', { count: group.unread_count }) }}</Badge>
                  </div>
                  <p v-if="group.body" class="mt-1 break-words text-sm leading-relaxed text-muted-foreground">{{ group.body }}</p>
                  <p class="mt-2 text-xs text-muted-foreground">{{ group.latest_at }}</p>
                </div>
                <div class="flex flex-wrap gap-2 sm:shrink-0">
                  <Button v-if="group.count > 1" type="button" variant="outline" size="sm" @click="toggleExpand(group.key)">
                    {{ expanded[group.key] ? t('community.notifications.collapse') : t('community.notifications.expand') }}
                  </Button>
                  <Button v-if="group.visit_url" as-child size="sm">
                    <Link :href="group.visit_url">{{ t('community.notifications.view') }}</Link>
                  </Button>
                </div>
              </div>
              <ul v-if="expanded[group.key] && group.items.length" class="mt-3 space-y-2 border-t pt-3">
                <li v-for="item in group.items" :key="item.id" class="flex flex-col gap-2 rounded-md bg-muted/25 p-2.5 text-sm sm:flex-row sm:items-start sm:justify-between">
                  <div class="min-w-0" :class="item.read ? 'text-muted-foreground' : ''">
                    <p class="font-medium">
                      <Badge v-if="item.auto_dismiss" variant="outline" class="mr-1 text-[10px]">{{ t('community.notifications.alert') }}</Badge>
                      {{ item.title }}
                    </p>
                    <p v-if="item.body" class="break-words text-xs leading-relaxed text-muted-foreground">{{ item.body }}</p>
                    <p class="mt-1 text-xs text-muted-foreground">{{ item.created_at }}</p>
                  </div>
                  <div class="flex flex-wrap gap-1 sm:shrink-0">
                    <Button v-if="!item.read" type="button" variant="outline" size="sm" @click="markRead(item.mark_read_url)">{{ t('community.notifications.markRead') }}</Button>
                    <Button as-child size="sm" variant="outline">
                      <Link :href="item.visit_url">{{ t('community.notifications.view') }}</Link>
                    </Button>
                  </div>
                </li>
              </ul>
            </article>
          </div>
        </div>
      </div>
    </section>
  </div>

  <p v-else class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
    {{ t('community.notifications.empty') }}
  </p>
</template>
