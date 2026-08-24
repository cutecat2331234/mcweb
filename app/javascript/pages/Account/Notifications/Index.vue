<script setup lang="ts">
import { computed, watch } from 'vue'
import { Link, router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import {
  Breadcrumb,
  BreadcrumbItem,
  Button,
  Card,
  Collapse,
  CollapseItem,
  Empty,
  Grid,
  GridItem,
  List,
  ListItem,
  PageHeader,
  Pagination,
  RadioGroup,
  Select,
  Space,
  Tag,
  TypographyParagraph,
  TypographyText,
} from '@mcweb/ui'
import { IconClose } from '@arco-design/web-vue/es/icon'
import PortalLayout from '@/layouts/PortalLayout.vue'
import { routes } from '@/lib/routes'
import { appendQueryParams } from '@/lib/utils'
import { commitNavigationEffect } from '@/lib/navigationReceipt'
import { confirm } from '@/lib/arcoConfirm'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

export interface NotificationGroup {
  key: string
  notification_type: string
  category: string
  title: string
  body: string | null
  count: number
  unread_count: number
  read: boolean
  latest_at: string
  visit_url: string | null
  delete_url: string | null
  items: Array<{
    id: number
    title: string
    body: string | null
    created_at: string
    visit_url: string | null
    mark_read_url: string
    delete_url: string
    read: boolean
    category: string
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

interface CategoryFilter {
  key: string
  label: string
}

interface PaginationMeta {
  page: number
  pages: number
  count: number
  from: number | null
  to: number | null
  prev: number | null
  next: number | null
}

const props = defineProps<{
  notificationGroups: NotificationGroup[]
  notificationSections?: NotificationSection[]
  activeCategory: string
  activeRead?: 'all' | 'unread'
  activeType?: string
  activePeriod?: string
  typeTabs?: TypeTab[]
  quickFilters?: QuickFilter[]
  periodFilters?: PeriodFilter[]
  activeFilters?: Array<{ param: string; label: string; value?: string }>
  categoryFilters: CategoryFilter[]
  unreadCount?: number
  dismissAlertsUrl?: string | null
  pagination: PaginationMeta
}>()

watch(
  () => props.dismissAlertsUrl,
  (url) => { void commitNavigationEffect(url, { method: 'patch' }) },
  { immediate: true },
)

const categoryOptions = computed(() => [
  { label: t('accountNotifications.all'), value: 'all' },
  ...props.categoryFilters.map((filter) => ({ label: filter.label, value: filter.key })),
])

const readOptions = computed(() => [
  { label: t('accountNotifications.allMessages'), value: 'all' },
  {
    label: props.unreadCount
      ? `${t('accountNotifications.unread')} (${props.unreadCount})`
      : t('accountNotifications.unread'),
    value: 'unread',
  },
])

const periodOptions = computed(() => (props.periodFilters || []).map((filter) => ({
  label: `${filter.label} (${filter.count})`,
  value: filter.period,
})))

const quickFilterOptions = computed(() => (props.quickFilters || []).map((filter) => ({
  label: filter.unread_count
    ? `${filter.label} (${filter.count}, ${t('accountNotifications.unreadCount', { count: filter.unread_count })})`
    : `${filter.label} (${filter.count})`,
  value: filter.type,
})))

const typeOptions = computed(() => (props.typeTabs || []).map((tab) => ({
  label: tab.unread_count
    ? `${tab.label} (${tab.count}, ${t('accountNotifications.unreadCount', { count: tab.unread_count })})`
    : `${tab.label} (${tab.count})`,
  value: tab.type,
})))

const activeQuickType = computed(() => props.quickFilters?.find((filter) => filter.active)?.type)

const displaySections = computed<NotificationSection[]>(() => {
  if (props.notificationSections?.length) return props.notificationSections
  if (!props.notificationGroups.length) return []
  return [{
    key: 'all',
    label: t('accountNotifications.all'),
    count: props.notificationGroups.length,
    groups: props.notificationGroups,
    timeline_sections: [],
    default_expanded: true,
  }]
})

const defaultSectionKeys = computed(() => displaySections.value
  .filter((section) => section.default_expanded)
  .map((section) => section.key))

function sectionTimelines(section: NotificationSection): TimelineSection[] {
  if (section.timeline_sections?.length) return section.timeline_sections
  if (!section.groups.length) return []
  return [{
    key: 'all',
    label: t('accountNotifications.all'),
    count: section.groups.length,
    groups: section.groups,
    default_expanded: true,
  }]
}

function defaultTimelineKeys(section: NotificationSection) {
  return sectionTimelines(section)
    .filter((timeline) => timeline.default_expanded)
    .map((timeline) => `${section.key}-${timeline.key}`)
}

function filterParams(overrides: Record<string, string | undefined> = {}) {
  const category = Object.hasOwn(overrides, 'category')
    ? overrides.category
    : (props.activeCategory === 'all' ? undefined : props.activeCategory)
  const read = Object.hasOwn(overrides, 'read')
    ? overrides.read
    : (props.activeRead === 'unread' ? 'unread' : undefined)
  const type = Object.hasOwn(overrides, 'type')
    ? overrides.type
    : (props.activeType || undefined)
  const period = Object.hasOwn(overrides, 'period')
    ? overrides.period
    : (props.activePeriod || undefined)
  return { category, read, type, period }
}

function currentListParams() {
  return {
    ...filterParams(),
    page: props.pagination.page > 1 ? String(props.pagination.page) : undefined,
  }
}

function visitNotification(url: string) {
  router.visit(url)
}

function markAllRead() {
  router.patch(appendQueryParams(`${routes.accountNotifications}/mark_all_read`, filterParams()))
}

function dismissAlerts() {
  router.patch(`${routes.accountNotifications}/dismiss_alerts`)
}

const filterNavigationOptions = {
  preserveState: true,
  preserveScroll: true,
  replace: true,
}

function switchCategory(value: unknown) {
  const category = String(value)
  router.get(
    routes.accountNotifications,
    filterParams({ category: category === 'all' ? undefined : category, type: undefined }),
    filterNavigationOptions,
  )
}

function switchRead(value: string | number | boolean) {
  const read = String(value)
  router.get(
    routes.accountNotifications,
    filterParams({ read: read === 'unread' ? 'unread' : undefined }),
    filterNavigationOptions,
  )
}

function switchPeriod(value: unknown) {
  router.get(
    routes.accountNotifications,
    filterParams({ period: typeof value === 'string' && value ? value : undefined }),
    filterNavigationOptions,
  )
}

function switchType(value: unknown) {
  router.get(
    routes.accountNotifications,
    filterParams({ type: typeof value === 'string' && value ? value : undefined }),
    filterNavigationOptions,
  )
}

function markRead(url: string) {
  router.patch(appendQueryParams(url, currentListParams()), {}, { preserveScroll: true })
}

async function deleteNotification(url: string) {
  const ok = await confirm({
    title: t('accountNotifications.deleteTitle'),
    message: t('accountNotifications.deleteConfirm'),
    confirmLabel: t('accountNotifications.delete'),
    cancelLabel: t('common.cancel'),
    variant: 'destructive',
  })
  if (!ok) return

  router.delete(appendQueryParams(url, currentListParams()), { preserveScroll: true })
}

function removeFilter(filter: { param: string }) {
  const overrides: Record<string, string | undefined> = {}
  if (filter.param === 'category') overrides.category = undefined
  if (filter.param === 'read') overrides.read = undefined
  if (filter.param === 'period') overrides.period = undefined
  if (filter.param === 'type') overrides.type = undefined
  router.get(routes.accountNotifications, filterParams(overrides), filterNavigationOptions)
}

function clearAllFilters() {
  router.get(routes.accountNotifications, {}, filterNavigationOptions)
}

function changePage(page: number) {
  if (page === props.pagination.page) return
  router.get(
    routes.accountNotifications,
    { ...filterParams(), page: String(page) },
    { preserveState: true, preserveScroll: true },
  )
}

function categoryLabel(category: string) {
  return props.categoryFilters.find((filter) => filter.key === category)?.label || category
}
</script>

<template>
  <Space direction="vertical" fill size="large">
    <PageHeader
      :show-back="false"
      :title="t('accountNotifications.title')"
    >
      <template #breadcrumb>
        <Breadcrumb>
          <BreadcrumbItem><Link :href="routes.home">{{ t('breadcrumb.home') }}</Link></BreadcrumbItem>
          <BreadcrumbItem><Link :href="routes.account">{{ t('breadcrumb.account') }}</Link></BreadcrumbItem>
          <BreadcrumbItem>{{ t('accountNotifications.title') }}</BreadcrumbItem>
        </Breadcrumb>
      </template>
      <Space wrap>
        <Button type="secondary" size="small" @click="markAllRead">
          {{ t('accountNotifications.markAllRead') }}
        </Button>
        <Button type="secondary" size="small" @click="dismissAlerts">
          {{ t('accountNotifications.dismissAlerts') }}
        </Button>
      </Space>
    </PageHeader>

    <Card :bordered="true">
      <Space direction="vertical" fill size="medium">
        <Grid :cols="{ xs: 1, md: 2 }" :col-gap="16" :row-gap="16">
          <GridItem>
            <Space direction="vertical" fill size="small">
              <TypographyText type="secondary">{{ t('accountNotifications.categoryFilter') }}</TypographyText>
              <Select
                :model-value="activeCategory"
                :options="categoryOptions"
                :aria-label="t('accountNotifications.categoryFilter')"
                @change="switchCategory"
              />
            </Space>
          </GridItem>
          <GridItem>
            <Space direction="vertical" fill size="small">
              <TypographyText type="secondary">{{ t('accountNotifications.readFilter') }}</TypographyText>
              <RadioGroup
                :model-value="activeRead || 'all'"
                :options="readOptions"
                :aria-label="t('accountNotifications.readFilter')"
                type="button"
                @change="switchRead"
              />
            </Space>
          </GridItem>
          <GridItem v-if="periodOptions.length">
            <Space direction="vertical" fill size="small">
              <TypographyText type="secondary">{{ t('accountNotifications.timeFilter') }}</TypographyText>
              <Select
                :model-value="activePeriod || undefined"
                :options="periodOptions"
                :aria-label="t('accountNotifications.timeFilter')"
                allow-clear
                @change="switchPeriod"
              />
            </Space>
          </GridItem>
          <GridItem v-if="quickFilterOptions.length">
            <Space direction="vertical" fill size="small">
              <TypographyText type="secondary">{{ t('accountNotifications.quickFilter') }}</TypographyText>
              <Select
                :model-value="activeQuickType"
                :options="quickFilterOptions"
                :aria-label="t('accountNotifications.quickFilter')"
                allow-clear
                @change="switchType"
              />
            </Space>
          </GridItem>
          <GridItem v-if="typeOptions.length">
            <Space direction="vertical" fill size="small">
              <TypographyText type="secondary">{{ t('accountNotifications.typeFilter') }}</TypographyText>
              <Select
                :model-value="activeType || undefined"
                :options="typeOptions"
                :aria-label="t('accountNotifications.typeFilter')"
                allow-clear
                @change="switchType"
              />
            </Space>
          </GridItem>
        </Grid>

        <Space v-if="activeFilters?.length" wrap>
          <TypographyText type="secondary">{{ t('accountNotifications.activeFilters') }}</TypographyText>
          <Space
            v-for="filter in activeFilters"
            :key="`${filter.param}-${filter.value || filter.label}`"
          >
            <Tag color="arcoblue">{{ filter.label }}</Tag>
            <Button
              type="text"
              size="mini"
              :aria-label="`${t('accountNotifications.removeFilter')}: ${filter.label}`"
              :title="t('accountNotifications.removeFilter')"
              @click="removeFilter(filter)"
            >
              <template #icon><IconClose /></template>
            </Button>
          </Space>
          <Button type="text" size="small" @click="clearAllFilters">
            {{ t('accountNotifications.clearAll') }}
          </Button>
        </Space>
      </Space>
    </Card>

    <Collapse
      v-if="displaySections.length"
      :default-active-key="defaultSectionKeys"
      expand-icon-position="right"
    >
      <CollapseItem
        v-for="section in displaySections"
        :key="section.key"
      >
        <template #header>
          <Space>
            <TypographyText>{{ section.label }}</TypographyText>
            <Tag bordered>{{ section.count }}</Tag>
          </Space>
        </template>

        <Collapse
          :default-active-key="defaultTimelineKeys(section)"
          expand-icon-position="right"
        >
          <CollapseItem
            v-for="timeline in sectionTimelines(section)"
            :key="`${section.key}-${timeline.key}`"
          >
            <template #header>
              <Space>
                <TypographyText>{{ timeline.label }}</TypographyText>
                <Tag bordered>{{ timeline.count }}</Tag>
              </Space>
            </template>

            <Space direction="vertical" fill size="medium">
              <Card
                v-for="group in timeline.groups"
                :key="group.key"
                :bordered="true"
              >
                <Space direction="vertical" fill size="small">
                  <Space wrap>
                    <Tag bordered>{{ categoryLabel(group.category) }}</Tag>
                    <TypographyText class="break-words">{{ group.title }}</TypographyText>
                    <Tag v-if="group.count > 1" color="arcoblue">{{ group.count }}</Tag>
                    <Tag v-if="group.unread_count" color="orange">
                      {{ t('accountNotifications.unreadCount', { count: group.unread_count }) }}
                    </Tag>
                  </Space>
                  <TypographyParagraph v-if="group.body" type="secondary" class="break-words">
                    {{ group.body }}
                  </TypographyParagraph>
                  <TypographyText type="secondary">{{ group.latest_at }}</TypographyText>

                  <Space wrap>
                    <Button
                      v-if="group.items.length === 1 && !group.items[0]?.read"
                      type="secondary"
                      size="small"
                      @click="markRead(group.items[0].mark_read_url)"
                    >
                      {{ t('accountNotifications.markRead') }}
                    </Button>
                    <Button
                      v-if="group.visit_url"
                      type="primary"
                      size="small"
                      @click="visitNotification(group.visit_url)"
                    >
                      {{ t('accountNotifications.view') }}
                    </Button>
                    <Button
                      v-if="group.delete_url"
                      type="outline"
                      status="danger"
                      size="small"
                      @click="deleteNotification(group.delete_url)"
                    >
                      {{ t('accountNotifications.delete') }}
                    </Button>
                  </Space>

                  <Collapse v-if="group.count > 1" :bordered="true">
                    <CollapseItem :key="`items-${group.key}`">
                      <template #header>
                        {{ t('accountNotifications.expand') }} ({{ group.count }})
                      </template>
                      <List :bordered="false" :split="true">
                        <ListItem
                          v-for="item in group.items"
                          :key="item.id"
                        >
                          <Space direction="vertical" fill size="small">
                            <Space wrap>
                              <Tag v-if="item.auto_dismiss" color="orange">
                                {{ t('accountNotifications.alert') }}
                              </Tag>
                              <TypographyText class="break-words">{{ item.title }}</TypographyText>
                            </Space>
                            <TypographyParagraph v-if="item.body" type="secondary" class="break-words">
                              {{ item.body }}
                            </TypographyParagraph>
                            <TypographyText type="secondary">{{ item.created_at }}</TypographyText>
                            <Space wrap>
                              <Button
                                v-if="!item.read"
                                type="text"
                                size="small"
                                @click="markRead(item.mark_read_url)"
                              >
                                {{ t('accountNotifications.markRead') }}
                              </Button>
                              <Button
                                v-if="item.visit_url"
                                type="text"
                                size="small"
                                @click="visitNotification(item.visit_url)"
                              >
                                {{ t('accountNotifications.view') }}
                              </Button>
                              <Button
                                type="text"
                                status="danger"
                                size="small"
                                @click="deleteNotification(item.delete_url)"
                              >
                                {{ t('accountNotifications.delete') }}
                              </Button>
                            </Space>
                          </Space>
                        </ListItem>
                      </List>
                    </CollapseItem>
                  </Collapse>
                </Space>
              </Card>
            </Space>
          </CollapseItem>
        </Collapse>
      </CollapseItem>
    </Collapse>

    <Card v-else :bordered="true">
      <Empty :description="t('accountNotifications.empty')" />
    </Card>

    <Pagination
      v-if="pagination.pages > 1"
      :total="pagination.count"
      :current="pagination.page"
      :page-size="50"
      :hide-on-single-page="true"
      :show-total="true"
      @change="changePage"
    />
  </Space>
</template>
