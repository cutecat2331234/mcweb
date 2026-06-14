<script setup lang="ts">
import { ref } from 'vue'
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
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

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
  statusOptions: Array<{ value: string; label: string }>
  exportUrl?: string
}>()

const q = ref(props.query)
const statusFilter = ref(props.status)

function reorder(url: string) {
  router.post(url)
}

function search() {
  router.get(routes.storeOrders, {
    q: q.value || undefined,
    status: statusFilter.value || undefined,
  }, { preserveState: true })
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
  </div>

  <form class="mb-4 flex flex-wrap items-center gap-2" @submit.prevent="search">
    <Input v-model="q" placeholder="搜索订单号…" class="max-w-xs" />
    <select v-model="statusFilter" class="h-9 rounded-md border border-input bg-transparent px-3 text-sm">
      <option value="">全部状态</option>
      <option v-for="opt in statusOptions" :key="opt.value" :value="opt.value">{{ opt.label }}</option>
    </select>
    <Button type="submit" size="sm">筛选</Button>
  </form>

  <div v-if="orders.length" class="rounded-lg border">
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>订单号</TableHead>
          <TableHead>状态</TableHead>
          <TableHead>金额</TableHead>
          <TableHead>时间</TableHead>
          <TableHead>操作</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        <TableRow v-for="order in orders" :key="order.id">
          <TableCell><Link :href="order.url" class="font-medium hover:underline">{{ order.order_number }}</Link></TableCell>
          <TableCell>{{ order.status_label || order.status }}</TableCell>
          <TableCell>{{ order.total_label }}</TableCell>
          <TableCell>{{ order.created_at }}</TableCell>
          <TableCell>
            <Button
              v-if="order.can_reorder && order.reorder_url"
              type="button"
              variant="outline"
              size="sm"
              @click="reorder(order.reorder_url!)"
            >
              再次购买
            </Button>
          </TableCell>
        </TableRow>
      </TableBody>
    </Table>
  </div>
  <Pagination v-if="orders.length" :pagination="pagination" :base-path="routes.storeOrders" />
  <p v-else class="text-sm text-muted-foreground">暂无订单。</p>
</template>
