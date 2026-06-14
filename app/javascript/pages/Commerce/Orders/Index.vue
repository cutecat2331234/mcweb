<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Table from '@/components/ui/Table.vue'
import TableBody from '@/components/ui/TableBody.vue'
import TableCell from '@/components/ui/TableCell.vue'
import TableHead from '@/components/ui/TableHead.vue'
import TableHeader from '@/components/ui/TableHeader.vue'
import TableRow from '@/components/ui/TableRow.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

defineProps<{
  orders: Array<{
    id: string
    order_number: string
    status: string
    total_label: string
    created_at: string
    url: string
  }>
}>()
</script>

<template>
  <PageHeader title="我的订单" />

  <div v-if="orders.length" class="rounded-lg border">
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>订单号</TableHead>
          <TableHead>状态</TableHead>
          <TableHead>金额</TableHead>
          <TableHead>时间</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        <TableRow v-for="order in orders" :key="order.id">
          <TableCell><Link :href="order.url" class="font-medium hover:underline">{{ order.order_number }}</Link></TableCell>
          <TableCell>{{ order.status }}</TableCell>
          <TableCell>{{ order.total_label }}</TableCell>
          <TableCell>{{ order.created_at }}</TableCell>
        </TableRow>
      </TableBody>
    </Table>
  </div>
  <p v-else class="text-sm text-muted-foreground">暂无订单。</p>
</template>
