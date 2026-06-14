<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Badge from '@/components/ui/Badge.vue'
import Button from '@/components/ui/Button.vue'
import Label from '@/components/ui/Label.vue'
import Textarea from '@/components/ui/Textarea.vue'
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
    status_label: string
    total_label: string
    can_pay: boolean
    can_cancel: boolean
    can_request_refund: boolean
    cancel_url: string
    refund_url: string
    payment_providers: Array<{ value: string; label: string }>
    default_provider: string
    refunds: Array<{
      amount_label: string
      status: string
      created_at: string
      customer_requested: boolean
    }>
    items: Array<{
      product_name: string
      variant_name: string | null
      quantity: number
      total_label: string
      fulfillment_status: string | null
    }>
    fulfillments: Array<{
      delivery_id: string
      status: string
      fulfilled_at: string | null
    }>
  }
}>()

const payForm = useForm({
  order_id: props.order.id,
  checkout: { provider: props.order.default_provider || 'fake' },
})
const cancelForm = useForm({})
const refundForm = useForm({ reason: '' })
</script>

<template>
  <PageHeader :title="`订单 ${order.order_number}`" :subtitle="`状态：${order.status_label}`" />

  <div class="mb-6 rounded-lg border">
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>商品</TableHead>
          <TableHead>数量</TableHead>
          <TableHead>小计</TableHead>
          <TableHead>发货</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        <TableRow v-for="(item, index) in order.items" :key="index">
          <TableCell>
            {{ item.product_name }}
            <span v-if="item.variant_name" class="text-muted-foreground"> — {{ item.variant_name }}</span>
          </TableCell>
          <TableCell>{{ item.quantity }}</TableCell>
          <TableCell>{{ item.total_label }}</TableCell>
          <TableCell>
            <Badge v-if="item.fulfillment_status" :variant="item.fulfillment_status === 'fulfilled' ? 'success' : 'default'">
              {{ item.fulfillment_status }}
            </Badge>
            <span v-else class="text-muted-foreground">—</span>
          </TableCell>
        </TableRow>
      </TableBody>
    </Table>
  </div>

  <div v-if="order.fulfillments.length" class="mb-6 rounded-lg border p-4">
    <h2 class="mb-3 text-sm font-semibold">发货记录</h2>
    <ul class="space-y-2 text-sm">
      <li v-for="fulfillment in order.fulfillments" :key="fulfillment.delivery_id" class="flex justify-between gap-4">
        <code class="text-xs">{{ fulfillment.delivery_id }}</code>
        <span>
          <Badge :variant="fulfillment.status === 'fulfilled' ? 'success' : 'default'">{{ fulfillment.status }}</Badge>
          <span v-if="fulfillment.fulfilled_at" class="ml-2 text-muted-foreground">{{ fulfillment.fulfilled_at }}</span>
        </span>
      </li>
    </ul>
  </div>

  <div v-if="order.refunds.length" class="mb-6 rounded-lg border p-4">
    <h2 class="mb-3 text-sm font-semibold">退款记录</h2>
    <ul class="space-y-2 text-sm">
      <li v-for="(refund, index) in order.refunds" :key="index" class="flex justify-between gap-4">
        <span>{{ refund.amount_label }}</span>
        <span>
          <Badge>{{ refund.status }}</Badge>
          <span v-if="refund.customer_requested" class="ml-2 text-xs text-muted-foreground">客户申请</span>
          <span class="ml-2 text-muted-foreground">{{ refund.created_at }}</span>
        </span>
      </li>
    </ul>
  </div>

  <p class="mb-6 font-medium">合计：{{ order.total_label }}</p>

  <form v-if="order.can_request_refund" class="mb-6 max-w-md space-y-3 rounded-lg border p-4" @submit.prevent="refundForm.post(order.refund_url)">
    <h2 class="text-sm font-semibold">申请退款</h2>
    <div class="space-y-2">
      <Label for="reason">退款原因（可选）</Label>
      <Textarea id="reason" v-model="refundForm.reason" rows="3" placeholder="请说明退款原因…" />
    </div>
    <Button type="submit" variant="outline" :disabled="refundForm.processing">提交退款申请</Button>
  </form>

  <div class="flex flex-wrap gap-3">
    <form v-if="order.can_pay && order.payment_providers.length > 1" class="flex items-center gap-2">
      <select v-model="payForm.checkout.provider" class="h-9 rounded-md border px-2 text-sm">
        <option v-for="provider in order.payment_providers" :key="provider.value" :value="provider.value">
          {{ provider.label }}
        </option>
      </select>
      <Button type="button" @click="payForm.post(routes.storeCheckout)">支付</Button>
    </form>
    <Button v-else-if="order.can_pay" type="button" @click="payForm.post(routes.storeCheckout)">支付</Button>
    <Button v-if="order.can_cancel" type="button" variant="outline" @click="cancelForm.post(order.cancel_url)">取消订单</Button>
    <Button as-child variant="outline">
      <Link :href="routes.storeOrders">返回订单列表</Link>
    </Button>
  </div>
</template>
