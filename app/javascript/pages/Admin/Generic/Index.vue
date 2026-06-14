<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
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

defineProps<{
  title: string
  subtitle?: string
  exportUrl?: string
  columns: AdminColumn[]
  rows: Array<Record<string, string>>
  actions?: AdminAction[]
}>()
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
    </div>
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
</template>
