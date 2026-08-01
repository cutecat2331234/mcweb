<script setup lang="ts">
import { router } from '@inertiajs/vue3'
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { confirm } from '@/lib/arcoConfirm'
import { isAdminSpaNavigationHref } from '@/lib/adminNavigation'
import HighRiskActionModal from '@/components/admin/HighRiskActionModal.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

export interface AdminColumn {
  key: string
  label: string
  link?: boolean
}

export interface AdminAction {
  label: string
  href: string
  external?: boolean
}

export interface AdminAlert {
  level: 'info' | 'warning' | 'error'
  message: string
}

export interface StatusTab {
  label: string
  href: string
  active: boolean
  count?: number
}

export interface PaginationMeta {
  page: number
  pages: number
  count: number
  from: number
  to: number
  prev: number | string | null
  next: number | string | null
}

export interface BulkRetryAction {
  label: string
  href: string
  ids: number[]
}

export interface DateFilterProps {
  created_from: string
  created_to: string
  action: string
}

export interface SearchFilterProps {
  query: string
  placeholder: string
  action: string
}

export interface AdminRow extends Record<string, string | undefined> {
  url?: string
  publicId?: string
}

type AdminTableRow = AdminRow & {
  __rowKey: string
}

const props = defineProps<{
  title: string
  subtitle?: string
  alerts?: AdminAlert[]
  exportUrl?: string
  columns: AdminColumn[]
  rows: Array<AdminRow>
  actions?: AdminAction[]
  statusTabs?: StatusTab[]
  eventTabs?: StatusTab[]
  kindTabs?: StatusTab[]
  bulkRetry?: BulkRetryAction | null
  dateFilter?: DateFilterProps | null
  search?: SearchFilterProps | null
  pagination?: PaginationMeta
  selectable?: boolean
  bulkModerateUrl?: string | null
  bulkOrderUrl?: string | null
  bulkOrderAuthorizationUrl?: string | null
  bulkOrderActions?: Array<{ label: string; action: string }>
}>()

const selectedPublicIds = ref<string[]>([])
const selectedBulkOrderAction = ref<{ label: string; action: string } | null>(null)
const bulkOrderModalVisible = ref(false)
const bulkOrderPayload = computed(() => ({
  order_ids: [ ...selectedPublicIds.value ],
  action_type: selectedBulkOrderAction.value?.action || '',
}))

const dateFrom = ref('')
const dateTo = ref('')
const searchQuery = ref('')
const isMobile = ref(false)
let viewportQuery: MediaQueryList | null = null
const selectableRowIds = computed(() =>
  props.rows.map((row) => row.publicId).filter((id): id is string => Boolean(id)),
)
const allRowsSelected = computed(
  () =>
    selectableRowIds.value.length > 0 &&
    selectableRowIds.value.every((id) => selectedPublicIds.value.includes(id)),
)
const someRowsSelected = computed(
  () => selectedPublicIds.value.length > 0 && !allRowsSelected.value,
)
const tableRows = computed<AdminTableRow[]>(() =>
  props.rows.map((row, index) => ({
    ...row,
    __rowKey: row.publicId || `admin-row-${index}`,
  })),
)

function syncViewport(event?: MediaQueryListEvent) {
  isMobile.value = event?.matches ?? viewportQuery?.matches ?? false
}

onMounted(() => {
  viewportQuery = window.matchMedia('(max-width: 767px)')
  syncViewport()
  viewportQuery.addEventListener('change', syncViewport)
})

onBeforeUnmount(() => {
  viewportQuery?.removeEventListener('change', syncViewport)
})

watch(
  () => props.dateFilter,
  (filter) => {
    dateFrom.value = filter?.created_from || ''
    dateTo.value = filter?.created_to || ''
  },
  { immediate: true }
)

watch(
  () => props.search?.query,
  (query) => {
    searchQuery.value = query || ''
  },
  { immediate: true },
)

watch(
  () => props.rows,
  () => {
    const visibleIds = new Set(selectableRowIds.value)
    selectedPublicIds.value = selectedPublicIds.value.filter((id) => visibleIds.has(id))
  },
)

async function submitBulkRetry(action: BulkRetryAction) {
  const ok = await confirm({
    title: action.label,
    message: t('admin.common.confirmAction', { action: action.label }),
  })
  if (!ok) return
  router.post(action.href, { ids: action.ids })
}

function applyDateFilter() {
  if (!props.dateFilter) return
  const params = new URLSearchParams(window.location.search)
  if (dateFrom.value) params.set('created_from', dateFrom.value)
  else params.delete('created_from')
  if (dateTo.value) params.set('created_to', dateTo.value)
  else params.delete('created_to')
  params.delete('page')
  const query = params.toString()
  router.visit(query ? `${props.dateFilter.action}?${query}` : props.dateFilter.action, {
    preserveScroll: true,
  })
}

function applySearch(value?: string) {
  if (!props.search) return
  if (typeof value === 'string') searchQuery.value = value

  const query = searchQuery.value.trim()
  router.get(
    props.search.action,
    query ? { q: query } : {},
    { preserveState: true, preserveScroll: true, replace: true },
  )
}

function toggleRowSelection(
  publicId: string | undefined,
  checked: boolean | Array<string | number | boolean>,
) {
  if (!publicId) return
  if (checked === true) {
    if (!selectedPublicIds.value.includes(publicId)) {
      selectedPublicIds.value = [ ...selectedPublicIds.value, publicId ]
    }
  } else {
    selectedPublicIds.value = selectedPublicIds.value.filter((id) => id !== publicId)
  }
}

function toggleSelectAll(checked: boolean | Array<string | number | boolean>) {
  if (checked !== true) {
    selectedPublicIds.value = []
    return
  }
  selectedPublicIds.value = [ ...selectableRowIds.value ]
}

function navigateTab(href: string | number) {
  if (typeof href === 'string' && href) router.visit(href)
}

function activeTab(tabs?: StatusTab[]) {
  return tabs?.find((tab) => tab.active)?.href ?? ''
}

function visitPage(page: number) {
  const url = new URL(window.location.href)
  url.searchParams.set('page', String(page))
  router.visit(`${url.pathname}${url.search}`, { preserveScroll: true })
}

function bulkModerate(action: string) {
  if (!props.bulkModerateUrl || selectedPublicIds.value.length === 0) return
  router.patch(props.bulkModerateUrl, {
    topic_ids: selectedPublicIds.value,
    action_type: action,
    return_to: window.location.pathname + window.location.search,
  }, {
    onSuccess: () => { selectedPublicIds.value = [] },
  })
}

function bulkOrder(item: { label: string; action: string }) {
  if (
    !props.bulkOrderUrl
    || !props.bulkOrderAuthorizationUrl
    || selectedPublicIds.value.length === 0
  ) return
  selectedBulkOrderAction.value = item
  bulkOrderModalVisible.value = true
}

function selectBulkOrder(action: string) {
  const item = props.bulkOrderActions?.find((candidate) => candidate.action === action)
  if (item) bulkOrder(item)
}

function bulkOrderCompleted() {
  selectedPublicIds.value = []
  selectedBulkOrderAction.value = null
  router.reload({ preserveScroll: true })
}
</script>

<template>
  <a-space direction="vertical" :size="16" fill>
    <a-page-header
      :title="title"
      :subtitle="subtitle"
      :show-back="false"
    >
      <template
        v-if="exportUrl || actions?.length || bulkRetry || selectedPublicIds.length"
        #extra
      >
        <a-space wrap size="small">
          <a-button
            v-if="exportUrl"
            :href="exportUrl"
            data-admin-hard-navigation
          >
            {{ t('admin.common.exportCsv') }}
          </a-button>
          <a-button
            v-for="(action, actionIndex) in actions || []"
            :key="action.href"
            :href="action.href"
            :target="action.external || !isAdminSpaNavigationHref(action.href) ? '_blank' : undefined"
            :rel="action.external || !isAdminSpaNavigationHref(action.href) ? 'noopener' : undefined"
            :data-admin-hard-navigation="action.external || !isAdminSpaNavigationHref(action.href) ? '' : undefined"
            :type="actionIndex === 0 ? 'primary' : 'secondary'"
          >
            {{ action.label }}
          </a-button>
          <a-button
            v-if="bulkRetry"
            type="outline"
            @click="submitBulkRetry(bulkRetry)"
          >
            {{ bulkRetry.label }}
          </a-button>
          <a-dropdown
            v-if="selectable && bulkModerateUrl && selectedPublicIds.length"
            trigger="click"
            position="br"
            @select="(value) => bulkModerate(String(value))"
          >
            <a-button type="outline">
              {{ t('components.bulkModerate.lockSelected', { count: selectedPublicIds.length }) }}
            </a-button>
            <template #content>
              <a-doption value="lock">
                {{ t('components.bulkModerate.lockSelected', { count: selectedPublicIds.length }) }}
              </a-doption>
              <a-doption value="unlock">
                {{ t('components.bulkModerate.unlockSelected') }}
              </a-doption>
              <a-doption value="archive">
                {{ t('components.bulkModerate.archiveSelected') }}
              </a-doption>
              <a-doption value="unarchive">
                {{ t('components.bulkModerate.unarchiveSelected') }}
              </a-doption>
            </template>
          </a-dropdown>
          <a-dropdown
            v-if="selectable && bulkOrderUrl && bulkOrderActions?.length && selectedPublicIds.length"
            trigger="click"
            position="br"
            @select="(value) => selectBulkOrder(String(value))"
          >
            <a-button type="primary">
              {{ t('admin.common.bulkAction') }}
              <a-badge :count="selectedPublicIds.length" />
            </a-button>
            <template #content>
              <a-doption
                v-for="item in bulkOrderActions"
                :key="item.action"
                :value="item.action"
              >
                {{ item.label }}
              </a-doption>
            </template>
          </a-dropdown>
        </a-space>
      </template>
    </a-page-header>

    <a-space v-if="alerts?.length" direction="vertical" :size="8" fill>
      <a-alert
        v-for="(alert, index) in alerts"
        :key="`${alert.level}-${index}`"
        :type="alert.level"
        show-icon
      >
        {{ alert.message }}
      </a-alert>
    </a-space>

    <a-card
      v-if="statusTabs?.length || eventTabs?.length || kindTabs?.length || dateFilter || search"
      :bordered="true"
    >
      <a-space direction="vertical" :size="16" fill>
        <a-space
          v-if="search"
          role="search"
          direction="vertical"
          fill
        >
          <a-input-search
            v-model="searchQuery"
            :placeholder="search.placeholder"
            search-button
            allow-clear
            @search="applySearch"
            @clear="applySearch('')"
          />
        </a-space>

        <a-tabs
          v-if="statusTabs?.length"
          :active-key="activeTab(statusTabs)"
          type="rounded"
          hide-content
          @change="navigateTab"
        >
          <a-tab-pane
            v-for="tab in statusTabs"
            :key="tab.href"
            :title="tab.count == null ? tab.label : `${tab.label} (${tab.count})`"
          />
        </a-tabs>

        <a-tabs
          v-if="eventTabs?.length"
          :active-key="activeTab(eventTabs)"
          type="rounded"
          hide-content
          @change="navigateTab"
        >
          <a-tab-pane
            v-for="tab in eventTabs"
            :key="tab.href"
            :title="tab.count == null ? tab.label : `${tab.label} (${tab.count})`"
          />
        </a-tabs>

        <a-tabs
          v-if="kindTabs?.length"
          :active-key="activeTab(kindTabs)"
          type="rounded"
          hide-content
          @change="navigateTab"
        >
          <a-tab-pane
            v-for="tab in kindTabs"
            :key="tab.href"
            :title="tab.label"
          />
        </a-tabs>

        <a-form
          v-if="dateFilter"
          :model="{}"
          layout="vertical"
          @submit="applyDateFilter"
        >
          <a-grid :cols="{ xs: 1, md: 2 }" :col-gap="16">
            <a-grid-item>
              <a-form-item :label="t('admin.common.dateFrom')">
                <a-date-picker
                  v-model="dateFrom"
                  value-format="YYYY-MM-DD"
                  format="YYYY-MM-DD"
                  allow-clear
                  long
                />
              </a-form-item>
            </a-grid-item>
            <a-grid-item>
              <a-form-item :label="t('admin.common.dateTo')">
                <a-date-picker
                  v-model="dateTo"
                  value-format="YYYY-MM-DD"
                  format="YYYY-MM-DD"
                  allow-clear
                  long
                />
              </a-form-item>
            </a-grid-item>
          </a-grid>
          <a-button html-type="submit" type="primary">
            {{ t('admin.common.filter') }}
          </a-button>
        </a-form>
      </a-space>
    </a-card>

    <a-card :bordered="true">
      <a-table
        v-if="!isMobile"
        :data="tableRows"
        :pagination="false"
        row-key="__rowKey"
        :bordered="{ cell: true }"
        :scroll="{ x: Math.max(720, columns.length * 180 + (selectable ? 52 : 0)) }"
        size="small"
        stripe
      >
        <template #columns>
          <a-table-column v-if="selectable" :width="52">
            <template #title>
              <a-checkbox
                :model-value="allRowsSelected"
                :indeterminate="someRowsSelected"
                @change="toggleSelectAll"
              />
            </template>
            <template #cell="{ record }">
              <a-checkbox
                v-if="record.publicId"
                :model-value="selectedPublicIds.includes(record.publicId)"
                @change="(checked) => toggleRowSelection(record.publicId, checked)"
              />
            </template>
          </a-table-column>
          <a-table-column
            v-for="(column, columnIndex) in columns"
            :key="column.key"
            :title="column.label"
            :data-index="column.key"
            :width="columnIndex === 0 ? 220 : 180"
            ellipsis
            tooltip
          >
            <template #cell="{ record }">
              <a-link
                v-if="column.link && record.url"
                :href="record.url"
                :target="isAdminSpaNavigationHref(record.url) ? undefined : '_blank'"
                :rel="isAdminSpaNavigationHref(record.url) ? undefined : 'noopener'"
                :data-admin-hard-navigation="isAdminSpaNavigationHref(record.url) ? undefined : ''"
              >
                {{ record[column.key] }}
              </a-link>
              <a-typography-text v-else>{{ record[column.key] }}</a-typography-text>
            </template>
          </a-table-column>
        </template>
        <template #empty>
          <a-empty :description="t('admin.ui.noResults')" />
        </template>
      </a-table>

      <a-list v-else :bordered="false">
        <a-list-item
          v-for="record in tableRows"
          :key="record.__rowKey"
        >
          <a-space direction="vertical" :size="12" fill>
            <a-checkbox
              v-if="selectable && record.publicId"
              :model-value="selectedPublicIds.includes(record.publicId)"
              :aria-label="String(record[columns[0]?.key] || record.publicId)"
              @change="(checked) => toggleRowSelection(record.publicId, checked)"
            />
            <a-descriptions :column="1" size="small" bordered>
              <a-descriptions-item
                v-for="column in columns"
                :key="column.key"
                :label="column.label"
              >
                <a-link
                  v-if="column.link && record.url"
                  :href="record.url"
                  :target="isAdminSpaNavigationHref(record.url) ? undefined : '_blank'"
                  :rel="isAdminSpaNavigationHref(record.url) ? undefined : 'noopener'"
                  :data-admin-hard-navigation="isAdminSpaNavigationHref(record.url) ? undefined : ''"
                >
                  {{ record[column.key] }}
                </a-link>
                <a-typography-text v-else>{{ record[column.key] }}</a-typography-text>
              </a-descriptions-item>
            </a-descriptions>
          </a-space>
        </a-list-item>
        <template #empty>
          <a-empty :description="t('admin.ui.noResults')" />
        </template>
      </a-list>
    </a-card>

    <a-row
      v-if="pagination && pagination.pages > 1"
      align="center"
      justify="space-between"
      :gutter="[12, 12]"
    >
      <a-typography-text type="secondary">
        {{ pagination.from }}–{{ pagination.to }} / {{ pagination.count }}
      </a-typography-text>
      <a-pagination
        :current="pagination.page"
        :total="pagination.pages"
        :page-size="1"
        :show-page-size="false"
        @change="visitPage"
      />
    </a-row>

    <HighRiskActionModal
      v-if="selectedBulkOrderAction && bulkOrderUrl && bulkOrderAuthorizationUrl"
      v-model:visible="bulkOrderModalVisible"
      :title="t('admin.highRisk.bulkTitle', { action: selectedBulkOrderAction.label })"
      :authorization-url="bulkOrderAuthorizationUrl"
      :action-url="bulkOrderUrl"
      method="PATCH"
      :payload="bulkOrderPayload"
      @completed="bulkOrderCompleted"
    />
  </a-space>
</template>
