<script setup lang="ts">
import { ref, watch, computed } from 'vue'
import { Link, router } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import Input from '@/components/ui/Input.vue'
import Table from '@/components/ui/Table.vue'
import TableBody from '@/components/ui/TableBody.vue'
import TableCell from '@/components/ui/TableCell.vue'
import TableHead from '@/components/ui/TableHead.vue'
import TableHeader from '@/components/ui/TableHeader.vue'
import TableRow from '@/components/ui/TableRow.vue'
import Button from '@/components/ui/Button.vue'
import Select from '@/components/ui/Select.vue'
import { routes } from '@/lib/routes'
import { prompt } from '@/lib/usePrompt'

defineOptions({ layout: PortalLayout })

interface StatusTab {
  label: string
  href: string
  active: boolean
  count?: number
  status?: string
}

interface TotalPreset {
  key: string
  label: string
  min_total: string | null
  max_total: string | null
  active: boolean
  href: string
}

const props = defineProps<{
  orders: Array<{
    id: string
    order_number: string
    status: string
    status_label: string
    total_label: string
    created_at: string
    url: string
    can_reorder?: boolean
    reorder_url?: string
  }>
  pagination: PaginationMeta
  query: string
  status: string
  createdAfter?: string
  createdBefore?: string
  minTotal?: string
  maxTotal?: string
  statusOptions: Array<{ value: string; label: string }>
  statusTabs?: StatusTab[]
  totalPresets?: TotalPreset[]
  activeFilters?: Array<{ param: string; label: string; value?: string }>
  exportUrl?: string
}>()

const q = ref(props.query)
const statusFilter = ref(props.status)
const createdAfter = ref(props.createdAfter || '')
const createdBefore = ref(props.createdBefore || '')
const minTotal = ref(props.minTotal || '')
const maxTotal = ref(props.maxTotal || '')
const exportCopied = ref(false)

const statusSelectOptions = computed(() => [
  { value: '', label: '全部状态' },
  ...props.statusOptions.map((opt) => ({ value: opt.value, label: opt.label })),
])

watch(() => props.status, (value) => {
  statusFilter.value = value
})

watch(() => props.query, (value) => {
  q.value = value
})

watch(() => props.createdAfter, (value) => {
  createdAfter.value = value || ''
})

watch(() => props.createdBefore, (value) => {
  createdBefore.value = value || ''
})

watch(() => props.minTotal, (value) => {
  minTotal.value = value || ''
})

watch(() => props.maxTotal, (value) => {
  maxTotal.value = value || ''
})

function orderParams(overrides: Record<string, string | undefined> = {}) {
  return {
    q: overrides.q ?? (q.value || undefined),
    status: overrides.status ?? (statusFilter.value || undefined),
    created_after: overrides.created_after ?? (createdAfter.value || undefined),
    created_before: overrides.created_before ?? (createdBefore.value || undefined),
    min_total: overrides.min_total ?? (minTotal.value || undefined),
    max_total: overrides.max_total ?? (maxTotal.value || undefined),
  }
}

function reorder(url: string) {
  router.post(url)
}

function search() {
  router.get(routes.storeOrders, orderParams(), { preserveState: true })
}

function removeFilter(filter: { param: string }) {
  const overrides: Record<string, string | undefined> = {}
  if (filter.param === 'q') {
    q.value = ''
    overrides.q = undefined
  }
  if (filter.param === 'status') {
    statusFilter.value = ''
    overrides.status = undefined
  }
  if (filter.param === 'created_after') {
    createdAfter.value = ''
    overrides.created_after = undefined
  }
  if (filter.param === 'created_before') {
    createdBefore.value = ''
    overrides.created_before = undefined
  }
  if (filter.param === 'min_total') {
    minTotal.value = ''
    overrides.min_total = undefined
  }
  if (filter.param === 'max_total') {
    maxTotal.value = ''
    overrides.max_total = undefined
  }
  router.get(routes.storeOrders, orderParams(overrides), { preserveState: true })
}

function applyTotalPreset(preset: TotalPreset) {
  minTotal.value = preset.min_total || ''
  maxTotal.value = preset.max_total || ''
  router.get(routes.storeOrders, orderParams({
    min_total: preset.min_total || undefined,
    max_total: preset.max_total || undefined,
  }), { preserveState: true })
}

function switchStatusTab(tab: StatusTab) {
  statusFilter.value = tab.status || ''
  router.get(routes.storeOrders, orderParams({ status: tab.status || undefined }), { preserveState: true })
}

async function copyExportUrl() {
  if (!props.exportUrl) return
  try {
    await navigator.clipboard.writeText(new URL(props.exportUrl, window.location.origin).href)
    exportCopied.value = true
    window.setTimeout(() => { exportCopied.value = false }, 2000)
  } catch {
    await prompt({
      title: '复制导出链接',
      defaultValue: props.exportUrl,
    })
  }
}
</script>

<template>
  <div class="mb-4 flex items-center justify-between gap-3">
    <PageHeader title="我的订单" />
    <Button as-child variant="outline" size="sm">
      <Link :href="routes.storePreferences">邮件偏好</Link>
    </Button>
    <Button v-if="exportUrl" as-child variant="outline" size="sm">
      <a :href="exportUrl">导出 CSV</a>
    </Button>
    <Button v-if="exportUrl" type="button" variant="outline" size="sm" @click="copyExportUrl">
      {{ exportCopied ? '已复制链接' : '复制导出链接' }}
    </Button>
  </div>

  <div v-if="statusTabs?.length" class="mb-4 flex flex-wrap gap-2">
    <button
      v-for="tab in statusTabs"
      :key="tab.href"
      type="button"
      class="rounded-md border px-3 py-1.5 text-sm"
      :class="tab.active ? 'border-primary bg-primary text-primary-foreground' : 'hover:bg-muted'"
      @click="switchStatusTab(tab)"
    >
      {{ tab.label }}<span v-if="tab.count != null" class="ml-1 opacity-80">({{ tab.count }})</span>
    </button>
  </div>

  <div v-if="totalPresets?.length" class="mb-4 flex flex-wrap items-center gap-2">
    <span class="text-xs text-muted-foreground">金额快捷：</span>
    <button
      v-for="preset in totalPresets"
      :key="preset.key"
      type="button"
      class="rounded-md border px-2.5 py-1 text-xs"
      :class="preset.active ? 'border-primary bg-primary text-primary-foreground' : 'hover:bg-muted'"
      @click="applyTotalPreset(preset)"
    >
      {{ preset.label }}
    </button>
  </div>

  <form class="mb-4 flex flex-wrap items-center gap-2" @submit.prevent="search">
    <Input v-model="q" placeholder="搜索订单号…" class="max-w-xs" />
    <Select v-model="statusFilter" :options="statusSelectOptions" size="sm" />
    <Input v-model="createdAfter" type="date" class="max-w-[10rem]" title="起始日期" />
    <Input v-model="createdBefore" type="date" class="max-w-[10rem]" title="截止日期" />
    <Input v-model="minTotal" type="number" min="0" step="0.01" placeholder="最低金额" class="max-w-[8rem]" title="最低金额" />
    <Input v-model="maxTotal" type="number" min="0" step="0.01" placeholder="最高金额" class="max-w-[8rem]" title="最高金额" />
    <Button type="submit" size="sm">筛选</Button>
  </form>

  <div v-if="activeFilters?.length" class="mb-4 flex flex-wrap items-center gap-2">
    <span class="text-xs text-muted-foreground">已选筛选：</span>
    <span
      v-for="filter in activeFilters"
      :key="`${filter.param}-${filter.value || filter.label}`"
      class="inline-flex items-center gap-1 rounded-full border border-primary/30 bg-primary/5 px-2.5 py-0.5 text-xs text-primary"
    >
      {{ filter.label }}
      <button type="button" class="hover:opacity-70" title="移除此筛选" @click="removeFilter(filter)">×</button>
    </span>
  </div>

  <div v-if="orders.length" class="rounded-lg border">
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>订单号</TableHead>
          <TableHead>状态</TableHead>
          <TableHead>金额</TableHead>
          <TableHead>时间</TableHead>
          <TableHead class="text-right">操作</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        <TableRow v-for="order in orders" :key="order.id">
          <TableCell>
            <Link :href="order.url" class="font-medium text-primary hover:underline">{{ order.order_number }}</Link>
          </TableCell>
          <TableCell>{{ order.status_label }}</TableCell>
          <TableCell>{{ order.total_label }}</TableCell>
          <TableCell class="text-muted-foreground">{{ order.created_at }}</TableCell>
          <TableCell class="text-right">
            <Button v-if="order.can_reorder && order.reorder_url" type="button" variant="outline" size="sm" @click="reorder(order.reorder_url!)">
              再次购买
            </Button>
          </TableCell>
        </TableRow>
      </TableBody>
    </Table>
  </div>
  <p v-else class="text-sm text-muted-foreground">暂无订单。</p>

  <Pagination v-if="pagination.pages > 1" :meta="pagination" class="mt-6" />
</template>
