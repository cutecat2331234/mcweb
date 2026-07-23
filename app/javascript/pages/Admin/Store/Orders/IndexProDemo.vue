<script setup lang="ts">
/**
 * POC sample page — "Store / Orders" rebuilt on Element Plus + the ProTable
 * wrapper, mounted at /admin/store/orders_pro_demo. Standalone on purpose: it
 * does NOT touch the shared Admin/Generic/Index.vue that renders dozens of live
 * lists. Rendered by Admin::Store::OrdersProDemoController with deterministic
 * demo data so the visual is stable regardless of DB state.
 */
import { router } from '@inertiajs/vue3'
import { ref } from 'vue'
import ProLayout from '@/components/admin-pro/ProLayout.vue'
import ProTable, {
  type ProColumn,
  type ProPagination,
  type ProBulkAction,
} from '@/components/admin-pro/ProTable.vue'

defineOptions({ layout: ProLayout })

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
}

const props = defineProps<{
  title: string
  subtitle?: string
  columns: ProColumn[]
  rows: OrderRow[]
  pagination: ProPagination
  statusOptions: Array<{ label: string; value: string }>
  currentStatus?: string
  query?: string
  exportUrl?: string
  bulkActionUrl?: string | null
  bulkActions?: ProBulkAction[]
}>()

const status = ref(props.currentStatus || '')
const q = ref(props.query || '')

/** Merge filter changes into the current query string, reset to page 1, navigate. */
function applyFilter(patch: Record<string, string | undefined>) {
  const url = new URL(window.location.href)
  Object.entries(patch).forEach(([key, value]) => {
    if (value) url.searchParams.set(key, value)
    else url.searchParams.delete(key)
  })
  url.searchParams.delete('page')
  router.get(url.pathname + url.search, {}, { preserveScroll: true })
}

/* Element Plus el-tag `type` mapping — the whole point of the demo: give every
 * order/payment state a semantic color so the list reads at a glance. */
function statusTagType(raw: string): 'success' | 'warning' | 'danger' | 'info' | 'primary' {
  switch (raw) {
    case 'paid':
    case 'fulfilled':
    case 'completed':
      return 'success'
    case 'pending':
    case 'awaiting_payment':
    case 'processing':
    case 'fulfilling':
      return 'warning'
    case 'cancelled':
    case 'failed':
      return 'danger'
    case 'refunded':
      return 'info'
    default:
      return 'primary'
  }
}

function paymentTagType(raw: string): 'success' | 'warning' | 'danger' | 'info' {
  switch (raw) {
    case 'paid':
      return 'success'
    case 'unpaid':
    case 'pending':
      return 'warning'
    case 'refunded':
      return 'info'
    default:
      return 'danger'
  }
}
</script>

<template>
  <div class="mb-6">
    <h1 class="text-xl font-semibold text-foreground">{{ title }}</h1>
    <p v-if="subtitle" class="mt-1 text-sm text-muted-foreground">{{ subtitle }}</p>
  </div>

  <el-alert
    class="mb-5"
    type="info"
    :closable="false"
    show-icon
    title="Element Plus 后台重做 · POC 样板页"
    description="本页用 Element Plus 2.14 + 自建 ProTable 重做“商城订单”列表：服务端分页 / URL 筛选 / Inertia 批量动作保持不变，新增列设置、密度切换、状态色徽章。原有后台未受影响。"
  />

  <ProTable
    :columns="columns"
    :rows="rows"
    :pagination="pagination"
    selectable
    :bulk-action-url="bulkActionUrl"
    :bulk-actions="bulkActions"
    bulk-method="patch"
    bulk-param-key="ids"
  >
    <template #toolbar-left>
      <el-segmented
        v-model="status"
        :options="statusOptions"
        @change="applyFilter({ status: status || undefined })"
      />
      <el-input
        v-model="q"
        placeholder="搜索订单号"
        clearable
        style="width: 220px"
        @keyup.enter="applyFilter({ q: q || undefined })"
        @clear="applyFilter({ q: undefined })"
      />
    </template>

    <template #toolbar-right>
      <el-button
        v-if="exportUrl"
        tag="a"
        :href="exportUrl"
      >
        导出 CSV
      </el-button>
    </template>

    <!-- Colored status badge -->
    <template #cell-status="{ row }">
      <el-tag :type="statusTagType((row as OrderRow).status)" effect="light" round>
        {{ (row as OrderRow).status_label }}
      </el-tag>
    </template>

    <!-- Colored payment badge -->
    <template #cell-payment_status="{ row }">
      <el-tag :type="paymentTagType((row as OrderRow).payment_status)" effect="plain">
        {{ (row as OrderRow).payment_label }}
      </el-tag>
    </template>

    <!-- Emphasized money column -->
    <template #cell-total="{ row }">
      <span class="font-medium tabular-nums">{{ (row as OrderRow).total }}</span>
    </template>
  </ProTable>
</template>
