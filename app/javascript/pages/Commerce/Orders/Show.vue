<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Table from '@/components/ui/Table.vue'
import TableBody from '@/components/ui/TableBody.vue'
import TableCell from '@/components/ui/TableCell.vue'
import TableHead from '@/components/ui/TableHead.vue'
import TableHeader from '@/components/ui/TableHeader.vue'
import TableRow from '@/components/ui/TableRow.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const props = defineProps<{
  order: {
    id: string
    order_number: string
    status: string
    total_label: string
    can_pay: boolean
    items: Array<{
      product_name: string
      variant_name: string | null
      quantity: number
      total_label: string
    }>
  }
}>()

const payForm = useForm({ order_id: props.order.id, checkout: { provider: 'fake' } })
</script>

<template>
  <PageHeader :title="`订单 ${order.order_number}`" :subtitle="`状态：${order.status}`" />

  <div class="mb-6 rounded-lg border">
    <Table>
      <TableHeader><TableRow><TableHead>商品</TableHead><TableHead>数量</TableHead><TableHead>小计</TableHead></TableRow></TableHeader>
      <TableBody>
        <TableRow v-for="(item, index) in order.items" :key="index">
          <TableCell>
            {{ item.product_name }}
            <span v-if="item.variant_name" class="text-muted-foreground"> — {{ item.variant_name }}</span>
          </TableCell>
          <TableCell>{{ item.quantity }}</TableCell>
          <TableCell>{{ item.total_label }}</TableCell>
        </TableRow>
      </TableBody>
    </Table>
  </div>

  <p class="mb-6 font-medium">合计：{{ order.total_label }}</p>

  <div class="flex gap-3">
    <Button v-if="order.can_pay" type="button" @click="payForm.post(routes.storeCheckout)">支付</Button>
    <Button as-child variant="outline">
      <Link :href="routes.storeOrders">返回订单列表</Link>
    </Button>
  </div>
</template>
