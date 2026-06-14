<script setup lang="ts">
import { Link, router, useForm } from '@inertiajs/vue3'
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
    notes: string | null
    subtotal_label?: string | null
    discount_label?: string | null
    coupon_code?: string | null
    total_label: string
    receipt_url: string
    receipt_pdf_url: string
    can_pay: boolean
    can_cancel: boolean
    can_request_refund: boolean
    can_download_receipt: boolean
    cancel_url: string
    refund_url: string
    refund_pending?: boolean
    reorder_url?: string
    can_reorder?: boolean
    payment_providers: Array<{ value: string; label: string }>
    default_provider: string
    refunds: Array<{
      amount_label: string
      status: string
      status_label: string
      reason: string | null
      created_at: string
      customer_requested: boolean
    }>
    events: Array<{
      event_type: string
      label: string
      created_at: string
    }>
    items: Array<{
      id?: number
      product_name: string
      variant_name: string | null
      quantity: number
      total_label: string
      product_url?: string | null
      ask_question_url?: string | null
      discussion_url?: string | null
      fulfillment_status: string | null
      fulfillment_status_label?: string | null
      download_url?: string | null
      refresh_download_url?: string | null
    }>
    downloads?: Array<{ product_name: string; url: string }>
    fulfillments: Array<{
      delivery_id: string
      status: string
      status_label?: string
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
const reorderForm = useForm({})

function refreshDownload(url: string) {
  router.post(url)
}
</script>

<template>
  <PageHeader :title="`订单 ${order.order_number}`" :subtitle="`状态：${order.status_label}`" />

  <p v-if="order.notes" class="mb-4 rounded-lg border p-4 text-sm">
    <span class="font-medium">订单备注：</span>{{ order.notes }}
  </p>

  <p v-if="order.refund_pending" class="mb-4 rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
    退款申请审核中，请耐心等待。
  </p>

  <div v-if="order.downloads?.length" class="mb-6 rounded-lg border p-4">
    <h2 class="mb-3 text-sm font-semibold">数字商品下载</h2>
    <ul class="space-y-2 text-sm">
      <li v-for="(download, index) in order.downloads" :key="index" class="flex justify-between gap-4">
        <span>{{ download.product_name }}</span>
        <a :href="download.url" target="_blank" rel="noopener" class="text-primary hover:underline">下载</a>
      </li>
    </ul>
  </div>

  <div v-if="order.events.length" class="mb-6 rounded-lg border p-4">
    <h2 class="mb-3 text-sm font-semibold">订单时间线</h2>
    <ol class="space-y-2 text-sm">
      <li v-for="(event, index) in order.events" :key="index" class="flex justify-between gap-4">
        <span>{{ event.label }}</span>
        <span class="text-muted-foreground">{{ event.created_at }}</span>
      </li>
    </ol>
  </div>

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
            <Link v-if="item.product_url" :href="item.product_url" class="hover:underline">{{ item.product_name }}</Link>
            <template v-else>{{ item.product_name }}</template>
            <span v-if="item.variant_name" class="text-muted-foreground"> — {{ item.variant_name }}</span>
            <div v-if="item.ask_question_url || item.discussion_url" class="mt-1 flex gap-2">
              <Link v-if="item.ask_question_url" :href="item.ask_question_url" class="text-xs text-primary hover:underline">提问</Link>
              <Link v-if="item.discussion_url" :href="item.discussion_url" class="text-xs text-primary hover:underline">参与讨论</Link>
            </div>
          </TableCell>
          <TableCell>{{ item.quantity }}</TableCell>
          <TableCell>{{ item.total_label }}</TableCell>
          <TableCell>
            <Badge v-if="item.fulfillment_status_label || item.fulfillment_status" :variant="item.fulfillment_status === 'fulfilled' ? 'success' : 'default'">
              {{ item.fulfillment_status_label || item.fulfillment_status }}
            </Badge>
            <a v-if="item.download_url" :href="item.download_url" target="_blank" rel="noopener" class="ml-2 text-xs text-primary hover:underline">下载</a>
            <Button
              v-if="item.refresh_download_url"
              type="button"
              variant="ghost"
              size="sm"
              class="ml-1 h-auto px-1 text-xs"
              @click="refreshDownload(item.refresh_download_url!)"
            >
              刷新链接
            </Button>
            <span v-else-if="!item.fulfillment_status" class="text-muted-foreground">—</span>
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
          <Badge :variant="fulfillment.status === 'fulfilled' ? 'success' : 'default'">{{ fulfillment.status_label || fulfillment.status }}</Badge>
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
          <Badge>{{ refund.status_label || refund.status }}</Badge>
          <span v-if="refund.reason" class="ml-2 text-xs text-muted-foreground">{{ refund.reason }}</span>
          <span v-if="refund.customer_requested" class="ml-2 text-xs text-muted-foreground">客户申请</span>
          <span class="ml-2 text-muted-foreground">{{ refund.created_at }}</span>
        </span>
      </li>
    </ul>
  </div>

  <p v-if="order.subtotal_label" class="mb-1 text-sm text-muted-foreground">小计：{{ order.subtotal_label }}</p>
  <p v-if="order.discount_label" class="mb-1 text-sm text-green-700">优惠{{ order.coupon_code ? ` (${order.coupon_code})` : '' }}：−{{ order.discount_label }}</p>
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
    <Button v-if="order.can_reorder && order.reorder_url" type="button" variant="outline" @click="reorderForm.post(order.reorder_url)">再次购买</Button>
    <Button v-if="order.can_download_receipt" as-child variant="outline">
      <a :href="order.receipt_url" target="_blank" rel="noopener">HTML 收据</a>
    </Button>
    <Button v-if="order.can_download_receipt" as-child variant="outline">
      <a :href="order.receipt_pdf_url">PDF 收据</a>
    </Button>
    <Button as-child variant="outline">
      <Link :href="routes.storeOrders">返回订单列表</Link>
    </Button>
  </div>
</template>
