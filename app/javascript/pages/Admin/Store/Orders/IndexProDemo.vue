<script setup lang="ts">
import { computed, ref } from 'vue'
import { Link, router } from '@inertiajs/vue3'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

interface OrderRow {
  publicId: string
  order_number: string
  customer: string
  status: string
  status_label: string
  payment_status: string
  payment_label: string
  total: string
  created_at: string
  url?: string
  [key: string]: unknown
}

interface OrderColumn {
  key: string
  label: string
  link?: boolean
  width?: string | number
  minWidth?: string | number
  align?: 'left' | 'center' | 'right'
  fixed?: boolean | 'left' | 'right'
  sortable?: boolean
}

interface OrderPagination {
  page: number
  pages: number
  count: number
  from: number
  to: number
  prev: string | null
  next: string | null
}

interface OrderBulkAction {
  label: string
  action: string
  type?: 'primary' | 'success' | 'warning' | 'danger' | 'info'
}

type Density = 'large' | 'medium' | 'small'

const props = defineProps<{
  title: string
  subtitle?: string
  columns: OrderColumn[]
  rows: OrderRow[]
  pagination: OrderPagination
  statusOptions: Array<{ label: string; value: string }>
  currentStatus?: string
  query?: string
  exportUrl?: string
  bulkActionUrl?: string | null
  bulkActions?: OrderBulkAction[]
}>()

const status = ref(props.currentStatus || '')
const q = ref(props.query || '')
const density = ref<Density>('medium')
const visibleKeys = ref(props.columns.map((column) => column.key))
const selectedRowKeys = ref<Array<string | number>>([])

const visibleColumns = computed(() =>
  props.columns.filter((column) => visibleKeys.value.includes(column.key)),
)
const displaySubtitle = computed(() =>
  props.subtitle?.replace('Element Plus ProTable', 'Arco Design Table'),
)

const densityOptions: Array<{ label: string; value: Density }> = [
  { label: '宽松', value: 'large' },
  { label: '默认', value: 'medium' },
  { label: '紧凑', value: 'small' },
]

const rowSelection = {
  type: 'checkbox' as const,
  showCheckedAll: true,
  onlyCurrent: true,
  width: 46,
}

const pageSize = computed(() => {
  if (props.pagination.page > 1) {
    return Math.max(Math.round((props.pagination.from - 1) / (props.pagination.page - 1)), 1)
  }
  return Math.max(props.pagination.to - props.pagination.from + 1, 1)
})

function applyFilter(patch: Record<string, string | undefined>) {
  const url = new URL(window.location.href)
  Object.entries(patch).forEach(([key, value]) => {
    if (value) url.searchParams.set(key, value)
    else url.searchParams.delete(key)
  })
  url.searchParams.delete('page')
  router.get(url.pathname + url.search, {}, {
    preserveScroll: true,
    preserveState: true,
    replace: true,
  })
}

function goToPage(page: number) {
  const url = new URL(window.location.href)
  url.searchParams.set('page', String(page))
  router.get(url.pathname + url.search, {}, {
    preserveScroll: true,
    preserveState: true,
    replace: true,
  })
}

function runBulk(action: string) {
  if (!selectedRowKeys.value.length || !props.bulkActionUrl) return
  router.patch(
    props.bulkActionUrl,
    {
      ids: selectedRowKeys.value,
      action_type: action,
      return_to: window.location.pathname + window.location.search,
    },
    {
      preserveScroll: true,
      onSuccess: () => {
        selectedRowKeys.value = []
      },
    },
  )
}

function columnSorter(column: OrderColumn) {
  if (!column.sortable) return undefined
  return {
    sortDirections: ['ascend', 'descend'],
    sorter: (left: OrderRow, right: OrderRow) =>
      String(left[column.key] ?? '').localeCompare(
        String(right[column.key] ?? ''),
        undefined,
        { numeric: true },
      ),
  }
}

function statusTagColor(raw: string) {
  switch (raw) {
    case 'paid':
    case 'fulfilled':
    case 'completed':
      return 'green'
    case 'pending':
    case 'awaiting_payment':
    case 'processing':
    case 'fulfilling':
      return 'orange'
    case 'cancelled':
    case 'failed':
      return 'red'
    case 'refunded':
      return 'gray'
    default:
      return 'arcoblue'
  }
}

function bulkButtonStatus(type: OrderBulkAction['type']) {
  if (type === 'danger') return 'danger'
  if (type === 'warning') return 'warning'
  if (type === 'success') return 'success'
  return 'normal'
}
</script>

<template>
  <section class="admin-store-orders-arco-demo">
    <a-page-header
      :title="title"
      :subtitle="displaySubtitle"
      :show-back="false"
      class="mb-4 !px-0"
    />

    <a-alert
      class="mb-5"
      type="info"
      show-icon
      :closable="false"
      title="Arco Design 后台样板页"
      description="服务端分页、URL 筛选、批量动作、列设置、密度切换与状态徽章均保持可用。"
    />

    <a-card :bordered="true">
      <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
        <a-space wrap>
          <a-radio-group
            v-model="status"
            type="button"
            @change="applyFilter({ status: status || undefined })"
          >
            <a-radio
              v-for="option in statusOptions"
              :key="option.value"
              :value="option.value"
            >
              {{ option.label }}
            </a-radio>
          </a-radio-group>
          <a-input-search
            v-model="q"
            placeholder="搜索订单号"
            allow-clear
            search-button
            class="w-64"
            @search="applyFilter({ q: q || undefined })"
            @clear="applyFilter({ q: undefined })"
          />
        </a-space>

        <a-space wrap>
          <a-button
            v-for="action in bulkActions || []"
            v-show="selectedRowKeys.length"
            :key="action.action"
            :type="action.type === 'primary' ? 'primary' : 'secondary'"
            :status="bulkButtonStatus(action.type)"
            @click="runBulk(action.action)"
          >
            {{ action.label }}（{{ selectedRowKeys.length }}）
          </a-button>

          <a-link v-if="exportUrl" :href="exportUrl" data-admin-hard-navigation>
            导出 CSV
          </a-link>

          <a-select
            v-model="density"
            :options="densityOptions"
            class="w-24"
          />

          <a-popover trigger="click" position="br">
            <a-button>列设置</a-button>
            <template #content>
              <a-checkbox-group v-model="visibleKeys">
                <a-space direction="vertical">
                  <a-checkbox
                    v-for="column in columns"
                    :key="column.key"
                    :value="column.key"
                  >
                    {{ column.label }}
                  </a-checkbox>
                </a-space>
              </a-checkbox-group>
            </template>
          </a-popover>
        </a-space>
      </div>

      <a-table
        v-model:selected-keys="selectedRowKeys"
        :data="rows"
        row-key="publicId"
        :row-selection="rowSelection"
        :pagination="false"
        :size="density"
        :bordered="{ cell: true }"
        :scroll="{ x: 1080 }"
        stripe
      >
        <template #columns>
          <a-table-column
            v-for="column in visibleColumns"
            :key="column.key"
            :title="column.label"
            :data-index="column.key"
            :width="column.width"
            :min-width="column.minWidth || 120"
            :align="column.align || 'left'"
            :fixed="column.fixed"
            :sortable="columnSorter(column)"
            ellipsis
            tooltip
          >
            <template #cell="{ record }">
              <a-tag
                v-if="column.key === 'status'"
                :color="statusTagColor(record.status)"
              >
                {{ record.status_label }}
              </a-tag>
              <a-tag
                v-else-if="column.key === 'payment_status'"
                :color="statusTagColor(record.payment_status)"
              >
                {{ record.payment_label }}
              </a-tag>
              <a-typography-text
                v-else-if="column.key === 'total'"
                strong
                class="tabular-nums"
              >
                {{ record.total }}
              </a-typography-text>
              <Link
                v-else-if="column.link && record.url"
                :href="record.url"
                class="arco-link font-medium no-underline"
              >
                {{ record[column.key] }}
              </Link>
              <span v-else>{{ record[column.key] }}</span>
            </template>
          </a-table-column>
        </template>

        <template #empty>
          <a-empty />
        </template>
      </a-table>

      <div class="mt-4 flex flex-wrap items-center justify-between gap-3">
        <a-typography-text type="secondary">
          共 {{ pagination.count }} 条 · 显示第
          {{ pagination.from }}–{{ pagination.to }} 条
        </a-typography-text>
        <a-pagination
          v-if="pagination.pages > 1"
          :current="pagination.page"
          :total="pagination.count"
          :page-size="pageSize"
          :show-total="false"
          @change="goToPage"
        />
      </div>
    </a-card>
  </section>
</template>
