<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import { computed, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { confirm } from '@/lib/arcoConfirm'

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

export interface AdminRow extends Record<string, string> {
  url?: string
  publicId?: string
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
  pagination?: PaginationMeta
  selectable?: boolean
  bulkModerateUrl?: string | null
  bulkOrderUrl?: string | null
  bulkOrderActions?: Array<{ label: string; action: string }>
}>()

const selectedPublicIds = ref<string[]>([])

const dateFrom = ref('')
const dateTo = ref('')
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
const tableRows = computed(() =>
  props.rows.map((row, index) => ({
    ...row,
    __rowKey: row.publicId || `admin-row-${index}`,
  })),
)

watch(
  () => props.dateFilter,
  (filter) => {
    dateFrom.value = filter?.created_from || ''
    dateTo.value = filter?.created_to || ''
  },
  { immediate: true }
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

function toggleRowSelection(publicId: string, checked: boolean) {
  if (!publicId) return
  if (checked) {
    if (!selectedPublicIds.value.includes(publicId)) {
      selectedPublicIds.value = [ ...selectedPublicIds.value, publicId ]
    }
  } else {
    selectedPublicIds.value = selectedPublicIds.value.filter((id) => id !== publicId)
  }
}

function toggleSelectAll(checked: boolean) {
  if (!checked) {
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

async function bulkOrder(action: string) {
  if (!props.bulkOrderUrl || selectedPublicIds.value.length === 0) return
  const ok = await confirm({
    title: t('admin.common.bulkAction'),
    message: t('admin.common.bulkConfirm'),
  })
  if (!ok) return
  router.patch(props.bulkOrderUrl, {
    order_ids: selectedPublicIds.value,
    action_type: action,
    return_to: window.location.pathname + window.location.search,
  }, {
    onSuccess: () => { selectedPublicIds.value = [] },
  })
}
</script>

<template>
  <div class="admin-generic-index">
    <a-page-header
      :title="title"
      :subtitle="subtitle"
      :show-back="false"
      class="mb-4 !px-0"
    >
      <template
        v-if="exportUrl || actions?.length || bulkRetry || selectedPublicIds.length"
        #extra
      >
        <a-space wrap :size="[8, 8]">
          <a
            v-if="exportUrl"
            :href="exportUrl"
            class="arco-btn arco-btn-outline arco-btn-size-medium no-underline"
          >
            {{ t('admin.common.exportCsv') }}
          </a>
          <Link
            v-for="action in actions || []"
            :key="action.href"
            :href="action.href"
            class="arco-btn arco-btn-primary arco-btn-size-medium no-underline"
          >
            {{ action.label }}
          </Link>
          <a-button
            v-if="bulkRetry"
            type="outline"
            @click="submitBulkRetry(bulkRetry)"
          >
            {{ bulkRetry.label }}
          </a-button>
          <template v-if="selectable && bulkModerateUrl && selectedPublicIds.length">
            <a-button type="outline" @click="bulkModerate('lock')">
              {{ t('components.bulkModerate.lockSelected', { count: selectedPublicIds.length }) }}
            </a-button>
            <a-button type="outline" @click="bulkModerate('unlock')">
              {{ t('components.bulkModerate.unlockSelected') }}
            </a-button>
            <a-button type="outline" @click="bulkModerate('archive')">
              {{ t('components.bulkModerate.archiveSelected') }}
            </a-button>
            <a-button type="outline" @click="bulkModerate('unarchive')">
              {{ t('components.bulkModerate.unarchiveSelected') }}
            </a-button>
          </template>
          <template
            v-if="selectable && bulkOrderUrl && bulkOrderActions?.length && selectedPublicIds.length"
          >
            <a-button
              v-for="item in bulkOrderActions"
              :key="item.action"
              type="outline"
              @click="bulkOrder(item.action)"
            >
              {{ item.label }}（{{ selectedPublicIds.length }}）
            </a-button>
          </template>
        </a-space>
      </template>
    </a-page-header>

    <a-space v-if="alerts?.length" class="mb-4" direction="vertical" fill>
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
      v-if="statusTabs?.length || eventTabs?.length || kindTabs?.length || dateFilter"
      class="mb-4"
      :bordered="true"
    >
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

      <form
        v-if="dateFilter"
        class="flex flex-wrap items-end gap-3"
        @submit.prevent="applyDateFilter"
      >
        <label class="grid gap-1 text-sm">
          <span class="text-[var(--color-text-2)]">{{ t('admin.common.dateFrom') }}</span>
          <a-date-picker
            v-model="dateFrom"
            value-format="YYYY-MM-DD"
            format="YYYY-MM-DD"
            allow-clear
            style="width: 180px"
          />
        </label>
        <label class="grid gap-1 text-sm">
          <span class="text-[var(--color-text-2)]">{{ t('admin.common.dateTo') }}</span>
          <a-date-picker
            v-model="dateTo"
            value-format="YYYY-MM-DD"
            format="YYYY-MM-DD"
            allow-clear
            style="width: 180px"
          />
        </label>
        <a-button html-type="submit" type="primary">
          {{ t('admin.common.filter') }}
        </a-button>
      </form>
    </a-card>

    <a-card class="admin-generic-index__table-card" :bordered="true">
      <div class="overflow-x-auto">
        <a-table
          :data="tableRows"
          :pagination="false"
          row-key="__rowKey"
          :bordered="{ cell: true }"
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
                  @change="(checked: boolean) => toggleRowSelection(record.publicId, checked)"
                />
              </template>
            </a-table-column>
            <a-table-column
              v-for="column in columns"
              :key="column.key"
              :title="column.label"
              :data-index="column.key"
            >
              <template #cell="{ record }">
                <Link
                  v-if="column.link && record.url"
                  :href="record.url"
                  class="font-medium text-[rgb(var(--primary-6))] no-underline hover:underline"
                >
                  {{ record[column.key] }}
                </Link>
                <span v-else>{{ record[column.key] }}</span>
              </template>
            </a-table-column>
          </template>
          <template #empty>
            <a-empty :description="t('admin.ui.noResults')" />
          </template>
        </a-table>
      </div>
    </a-card>

    <div
      v-if="pagination && pagination.pages > 1"
      class="mt-4 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"
    >
      <span class="text-sm text-[var(--color-text-3)]">
        {{ pagination.from }}–{{ pagination.to }} / {{ pagination.count }}
      </span>
      <a-pagination
        :current="pagination.page"
        :total="pagination.pages"
        :page-size="1"
        :show-page-size="false"
        @change="visitPage"
      />
    </div>
  </div>
</template>

<style scoped>
.admin-generic-index :deep(.arco-tabs + .arco-tabs),
.admin-generic-index :deep(.arco-tabs + form) {
  margin-top: 12px;
}

.admin-generic-index__table-card :deep(.arco-card-body) {
  padding: 0;
}
</style>
