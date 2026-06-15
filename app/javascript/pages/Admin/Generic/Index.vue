<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination from '@/components/portal/Pagination.vue'
import Table from '@/components/ui/Table.vue'
import TableBody from '@/components/ui/TableBody.vue'
import TableCell from '@/components/ui/TableCell.vue'
import TableHead from '@/components/ui/TableHead.vue'
import TableHeader from '@/components/ui/TableHeader.vue'
import TableRow from '@/components/ui/TableRow.vue'

defineOptions({ layout: AdminLayout })

export interface AdminColumn {
  key: string
  label: string
  link?: boolean
}

export interface AdminAction {
  label: string
  href: string
}

export interface StatusTab {
  label: string
  href: string
  active: boolean
}

export interface PaginationMeta {
  page: number
  pages: number
  count: number
  from: number
  to: number
  prev: string | null
  next: string | null
}

export interface BulkRetryAction {
  label: string
  href: string
  ids: number[]
}

defineProps<{
  title: string
  subtitle?: string
  exportUrl?: string
  columns: AdminColumn[]
  rows: Array<Record<string, string>>
  actions?: AdminAction[]
  statusTabs?: StatusTab[]
  eventTabs?: StatusTab[]
  bulkRetry?: BulkRetryAction | null
  pagination?: PaginationMeta
}>()

function submitBulkRetry(action: BulkRetryAction) {
  if (!confirm(`确定要${action.label}吗？`)) return
  router.post(action.href, { ids: action.ids })
}
</script>

<template>
  <div class="mb-4 flex items-center justify-between">
    <PageHeader :title="title" :subtitle="subtitle" />
    <div class="flex gap-2">
      <a v-if="exportUrl" :href="exportUrl" class="inline-flex h-9 items-center rounded-md border px-3 text-sm hover:bg-muted">导出 CSV</a>
      <Link
        v-for="action in actions || []"
        :key="action.href"
        :href="action.href"
        class="rounded-md bg-primary px-3 py-1.5 text-sm text-primary-foreground no-underline hover:opacity-90"
      >
        {{ action.label }}
      </Link>
      <button
        v-if="bulkRetry"
        type="button"
        class="rounded-md border px-3 py-1.5 text-sm hover:bg-muted"
        @click="submitBulkRetry(bulkRetry)"
      >
        {{ bulkRetry.label }}
      </button>
    </div>
  </div>

  <div v-if="statusTabs?.length" class="mb-4 flex flex-wrap gap-2">
    <Link
      v-for="tab in statusTabs"
      :key="'status-' + tab.href"
      :href="tab.href"
      class="rounded-md border px-3 py-1.5 text-sm no-underline"
      :class="tab.active ? 'border-primary bg-primary text-primary-foreground' : 'hover:bg-muted'"
    >
      {{ tab.label }}
    </Link>
  </div>

  <div v-if="eventTabs?.length" class="mb-4 flex flex-wrap gap-2">
    <Link
      v-for="tab in eventTabs"
      :key="'event-' + tab.href"
      :href="tab.href"
      class="rounded-md border px-3 py-1.5 text-xs no-underline"
      :class="tab.active ? 'border-primary bg-primary text-primary-foreground' : 'hover:bg-muted'"
    >
      {{ tab.label }}
    </Link>
  </div>

  <div v-if="rows.length" class="rounded-lg border">
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead v-for="column in columns" :key="column.key">
            {{ column.label }}
          </TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        <TableRow v-for="(row, index) in rows" :key="index">
          <TableCell v-for="column in columns" :key="column.key">
            <Link
              v-if="column.link && row.url"
              :href="row.url"
              class="font-medium hover:underline"
            >
              {{ row[column.key] }}
            </Link>
            <span v-else>{{ row[column.key] }}</span>
          </TableCell>
        </TableRow>
      </TableBody>
    </Table>
  </div>

  <p v-else class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
    暂无数据。
  </p>

  <Pagination v-if="pagination && pagination.pages > 1" :meta="pagination" class="mt-4" />
</template>
