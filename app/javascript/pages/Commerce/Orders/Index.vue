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
import { useI18n } from 'vue-i18n'
import { routes } from '@/lib/routes'
import { prompt } from '@/lib/usePrompt'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

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
  { value: '', label: t('commerce.orders.allStatus') },
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
      title: t('commerce.orders.copyExportLink'),
      defaultValue: props.exportUrl,
    })
  }
}
</script>

<template>
  <div class="mb-4 flex items-center justify-between gap-3">
    <PageHeader :title="t('commerce.orders.title')" />
    <Button as-child variant="outline" size="sm">
      <Link :href="routes.storePreferences">{{ t('commerce.orders.emailPrefs') }}</Link>
    </Button>
    <Button v-if="exportUrl" as-child variant="outline" size="sm">
      <a :href="exportUrl">{{ t('commerce.orders.exportCsv') }}</a>
    </Button>
    <Button v-if="exportUrl" type="button" variant="outline" size="sm" @click="copyExportUrl">
      {{ exportCopied ? t('commerce.orders.linkCopied') : t('commerce.orders.copyExportLink') }}
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
    <span class="text-xs text-muted-foreground">{{ t('commerce.orders.amountPresets') }}</span>
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
    <Input v-model="q" :placeholder="t('commerce.orders.searchPlaceholder')" class="max-w-xs" />
    <Select v-model="statusFilter" :options="statusSelectOptions" size="sm" />
    <Input v-model="createdAfter" type="date" class="max-w-[10rem]" :title="t('commerce.orders.dateFrom')" />
    <Input v-model="createdBefore" type="date" class="max-w-[10rem]" :title="t('commerce.orders.dateTo')" />
    <Input v-model="minTotal" type="number" min="0" step="0.01" :placeholder="t('commerce.orders.minAmount')" class="max-w-[8rem]" :title="t('commerce.orders.minAmount')" />
    <Input v-model="maxTotal" type="number" min="0" step="0.01" :placeholder="t('commerce.orders.maxAmount')" class="max-w-[8rem]" :title="t('commerce.orders.maxAmount')" />
    <Button type="submit" size="sm">{{ t('commerce.orders.filter') }}</Button>
  </form>

  <div v-if="activeFilters?.length" class="mb-4 flex flex-wrap items-center gap-2">
    <span class="text-xs text-muted-foreground">{{ t('commerce.orders.activeFilters') }}</span>
    <span
      v-for="filter in activeFilters"
      :key="`${filter.param}-${filter.value || filter.label}`"
      class="inline-flex items-center gap-1 rounded-full border border-primary/30 bg-primary/5 px-2.5 py-0.5 text-xs text-primary"
    >
      {{ filter.label }}
      <button type="button" class="hover:opacity-70" :title="t('commerce.orders.removeFilter')" @click="removeFilter(filter)">×</button>
    </span>
  </div>

  <div v-if="orders.length" class="rounded-lg border">
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>{{ t('commerce.orders.orderNumber') }}</TableHead>
          <TableHead>{{ t('commerce.orders.status') }}</TableHead>
          <TableHead>{{ t('commerce.orders.amount') }}</TableHead>
          <TableHead>{{ t('commerce.orders.time') }}</TableHead>
          <TableHead class="text-right">{{ t('commerce.orders.actions') }}</TableHead>
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
              {{ t('commerce.orders.reorder') }}
            </Button>
          </TableCell>
        </TableRow>
      </TableBody>
    </Table>
  </div>
  <p v-else class="text-sm text-muted-foreground">{{ t('commerce.orders.empty') }}</p>

  <Pagination v-if="pagination.pages > 1" :meta="pagination" class="mt-6" />
</template>
