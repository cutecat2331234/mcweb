<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { Link, router, useForm } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Badge from '@/components/ui/Badge.vue'
import Button from '@/components/ui/Button.vue'
import Label from '@/components/ui/Label.vue'
import Input from '@/components/ui/Input.vue'
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
    shipping_address_label?: string | null
    shipping_method_label?: string | null
    tracking_number?: string | null
    shipping_carrier?: string | null
    shipped_at?: string | null
    tracking_url?: string | null
    packing_slip_url?: string | null
    subtotal_label?: string | null
    shipping_label?: string | null
    free_shipping?: boolean
    discount_label?: string | null
    coupon_code?: string | null
    gift_card_code?: string | null
    gift_card_amount_label?: string | null
    store_credit_amount_label?: string | null
    customer_notes?: Array<{ body: string; author: string; created_at: string }>
    gift_wrap_label?: string | null
    total_label: string
    receipt_url: string
    receipt_pdf_url: string
    can_pay: boolean
    can_confirm_free?: boolean
    can_cancel: boolean
    can_request_refund: boolean
    payment_expires_at?: string | null
    payment_expires_label?: string | null
    payment_expired?: boolean
    refund_window_expires_at?: string | null
    refund_window_expires_label?: string | null
    max_refund_cents?: number
    max_refund_label?: string | null
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
    restorations?: Array<{ label: string; amount_label: string }>
    events: Array<{
      event_type: string
      label: string
      created_at: string
    }>
    shipping_timeline?: Array<{
      key: string
      label: string
      state: 'done' | 'current' | 'pending'
      at: string | null
    }>
    delivery_estimate?: string | null
    items: Array<{
      id?: number
      product_name: string
      variant_name: string | null
      quantity: number
      gift_note?: string | null
      total_label: string
      product_url?: string | null
      product_public_id?: string | null
      ask_question_url?: string | null
      ask_question_return_order_id?: string | null
      questions?: Array<{
        id: number
        body: string
        created_at: string
        answers: Array<{ body: string; author: string; official: boolean; created_at: string }>
      }>
      discussion_url?: string | null
      fulfillment_status: string | null
      fulfillment_status_label?: string | null
      download_url?: string | null
      refresh_download_url?: string | null
      issued_gift_cards?: Array<{ code: string; balance_label: string; url: string }>
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
const cancelForm = useForm({ reason: '' })
const refundForm = useForm({ reason: '', amount_cents: 0 as number | '' })

onMounted(() => {
  if (props.order.max_refund_cents) {
    refundForm.amount_cents = props.order.max_refund_cents
  }
})
const questionForms = ref<Record<number, string>>({})

function submitItemQuestion(item: { product_public_id?: string | null; id?: number; ask_question_return_order_id?: string }) {
  if (!item.product_public_id || !item.id) return
  const body = questionForms.value[item.id]?.trim()
  if (!body) return
  router.post(`/app/store/products/${item.product_public_id}/questions`, {
    question: { body },
    order_item_id: item.id,
    return_order_id: item.ask_question_return_order_id,
  }, {
    preserveScroll: true,
    onSuccess: () => { if (item.id) questionForms.value[item.id] = '' },
  })
}
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

  <p v-if="order.shipping_address_label" class="mb-4 rounded-lg border p-4 text-sm">
    <span class="font-medium">收货地址：</span>{{ order.shipping_address_label }}
    <span v-if="order.shipping_method_label" class="mt-1 block text-muted-foreground">配送方式：{{ order.shipping_method_label }}</span>
  </p>
  <p v-if="order.tracking_number" class="mb-4 rounded-lg border p-4 text-sm">
    <span class="font-medium">物流信息：</span>
    {{ order.shipping_carrier || '快递' }} — {{ order.tracking_number }}
    <span v-if="order.shipped_at" class="text-muted-foreground">（{{ order.shipped_at }} 发货）</span>
    <span v-if="order.delivery_estimate" class="text-muted-foreground"> · {{ order.delivery_estimate }}</span>
    <a v-if="order.tracking_url" :href="order.tracking_url" target="_blank" rel="noopener" class="ml-2 text-primary hover:underline">查询物流</a>
  </p>

  <div v-if="order.shipping_timeline?.length" class="mb-6 rounded-lg border p-4">
    <h2 class="mb-4 text-sm font-semibold">物流进度</h2>
    <ol class="flex flex-wrap gap-2 sm:flex-nowrap sm:justify-between">
      <li
        v-for="step in order.shipping_timeline"
        :key="step.key"
        class="flex min-w-[4.5rem] flex-1 flex-col items-center text-center text-xs"
      >
        <span
          class="mb-2 flex h-8 w-8 items-center justify-center rounded-full border-2"
          :class="{
            'border-primary bg-primary text-primary-foreground': step.state === 'done',
            'border-primary bg-background text-primary': step.state === 'current',
            'border-muted-foreground/30 text-muted-foreground': step.state === 'pending',
          }"
        >
          {{ step.state === 'done' ? '✓' : step.state === 'current' ? '…' : '○' }}
        </span>
        <span :class="step.state === 'pending' ? 'text-muted-foreground' : 'font-medium'">{{ step.label }}</span>
        <span v-if="step.at" class="mt-1 text-[10px] text-muted-foreground">{{ step.at }}</span>
      </li>
    </ol>
  </div>

  <p v-if="order.payment_expires_label && (order.can_pay || order.can_confirm_free)" class="mb-4 rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
    请在 {{ order.payment_expires_label }} 前完成支付，超时订单将自动取消。
  </p>
  <p v-else-if="order.payment_expired" class="mb-4 rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-900">
    支付已超时（{{ order.payment_expires_label }}），订单可能已被自动取消。
  </p>

  <p v-if="order.refund_window_expires_label && order.can_request_refund" class="mb-4 rounded-lg border border-blue-200 bg-blue-50 px-4 py-3 text-sm text-blue-900">
  退款窗口将于 {{ order.refund_window_expires_label }} 关闭，请尽快申请。
  </p>
  <p v-else-if="order.refund_window_expires_label && !order.can_request_refund && order.status === 'paid'" class="mb-4 rounded-lg border px-4 py-3 text-sm text-muted-foreground">
  退款窗口已于 {{ order.refund_window_expires_label }} 关闭。
  </p>

  <p v-if="order.refund_pending" class="mb-4 rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
    退款申请审核中，请耐心等待。
  </p>

  <div v-if="order.downloads?.length" class="mb-6">
    <h2 class="mb-4 flex items-center gap-2 text-base font-semibold">
      <span class="flex h-7 w-7 items-center justify-center rounded-lg bg-primary/10 text-primary text-sm">↓</span>
      数字商品下载
    </h2>
    <div class="grid gap-3 sm:grid-cols-2">
      <a
        v-for="(download, index) in order.downloads"
        :key="index"
        :href="download.url"
        target="_blank"
        rel="noopener"
        class="group flex items-center gap-4 rounded-xl border border-border bg-card p-4 transition-all hover:border-primary/40 hover:shadow-lg hover:shadow-primary/5 no-underline"
      >
        <div class="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-gradient-to-br from-primary/20 to-blue-500/10 text-primary text-xl transition-all group-hover:from-primary/30">
          ⬇
        </div>
        <div class="min-w-0 flex-1">
          <p class="truncate font-medium text-foreground">{{ download.product_name }}</p>
          <p class="mt-0.5 text-xs text-muted-foreground">点击下载</p>
        </div>
        <span class="text-sm text-primary opacity-0 transition-opacity group-hover:opacity-100">→</span>
      </a>
    </div>
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
            <p v-if="item.gift_note" class="mt-1 text-xs text-muted-foreground">赠言：{{ item.gift_note }}</p>
            <div v-if="item.ask_question_url || item.discussion_url" class="mt-1 flex gap-2">
              <Link v-if="item.discussion_url" :href="item.discussion_url" class="text-xs text-primary hover:underline">参与讨论</Link>
            </div>
            <div v-if="item.product_public_id && item.id" class="mt-2 space-y-2">
              <div v-for="q in item.questions || []" :key="q.id" class="rounded border bg-muted/30 p-2 text-xs">
                <p class="font-medium">Q: {{ q.body }}</p>
                <p v-for="(a, ai) in q.answers" :key="ai" class="mt-1 text-muted-foreground">
                  {{ a.official ? '官方' : a.author }}：{{ a.body }}
                </p>
              </div>
              <div class="flex gap-2">
                <Textarea v-model="questionForms[item.id]" rows="2" placeholder="就此商品提问…" class="text-xs" />
                <Button type="button" size="sm" variant="outline" @click="submitItemQuestion(item)">提问</Button>
              </div>
            </div>
            <ul v-if="item.issued_gift_cards?.length" class="mt-2 space-y-1 text-xs text-green-700">
              <li v-for="card in item.issued_gift_cards" :key="card.code">
                礼品卡 <Link :href="card.url" class="font-mono underline">{{ card.code }}</Link>（{{ card.balance_label }}）
              </li>
            </ul>
          </TableCell>
          <TableCell>{{ item.quantity }}</TableCell>
          <TableCell>{{ item.total_label }}</TableCell>
          <TableCell>
            <Badge v-if="item.fulfillment_status_label || item.fulfillment_status" :variant="item.fulfillment_status === 'fulfilled' ? 'success' : 'default'">
              {{ item.fulfillment_status_label || item.fulfillment_status }}
            </Badge>
            <a
              v-if="item.download_url"
              :href="item.download_url"
              target="_blank"
              rel="noopener"
              class="ml-2 inline-flex items-center gap-1 rounded-md bg-primary/10 px-2 py-0.5 text-xs font-medium text-primary transition-colors no-underline hover:bg-primary/20"
            >
              ⬇ 下载
            </a>
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

  <div v-if="order.customer_notes?.length" class="mb-6 rounded-lg border p-4">
    <h2 class="mb-3 text-sm font-semibold">商家留言</h2>
    <ul class="space-y-2 text-sm">
      <li v-for="(note, index) in order.customer_notes" :key="index">
        <p>{{ note.body }}</p>
        <p class="mt-1 text-xs text-muted-foreground">{{ note.author }} · {{ note.created_at }}</p>
      </li>
    </ul>
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

  <div v-if="order.restorations?.length" class="mb-6 rounded-lg border border-green-200 bg-green-50 p-4 dark:border-green-900 dark:bg-green-950">
    <h2 class="mb-3 text-sm font-semibold text-green-900 dark:text-green-100">退款恢复明细</h2>
    <ul class="space-y-1 text-sm text-green-800 dark:text-green-200">
      <li v-for="(item, index) in order.restorations" :key="index" class="flex justify-between gap-4">
        <span>{{ item.label }}</span>
        <span class="font-medium">{{ item.amount_label }}</span>
      </li>
    </ul>
  </div>

  <p v-if="order.subtotal_label" class="mb-1 text-sm text-muted-foreground">小计：{{ order.subtotal_label }}</p>
  <p v-if="order.shipping_label" class="mb-1 text-sm text-muted-foreground">运费：{{ order.free_shipping ? '免运费' : order.shipping_label }}</p>
  <p v-if="order.gift_wrap_label" class="mb-1 text-sm text-muted-foreground">礼品包装：{{ order.gift_wrap_label }}</p>
  <p v-if="order.discount_label" class="mb-1 text-sm text-green-700">优惠{{ order.coupon_code ? ` (${order.coupon_code})` : '' }}：−{{ order.discount_label }}</p>
  <p v-if="order.gift_card_amount_label" class="mb-1 text-sm text-green-700">礼品卡{{ order.gift_card_code ? ` (${order.gift_card_code})` : '' }}：−{{ order.gift_card_amount_label }}</p>
  <p v-if="order.store_credit_amount_label" class="mb-1 text-sm text-green-700">商店余额抵扣：−{{ order.store_credit_amount_label }}</p>
  <p class="mb-6 font-medium">合计：{{ order.total_label }}</p>

  <form v-if="order.can_request_refund" class="mb-6 max-w-md space-y-3 rounded-lg border p-4" @submit.prevent="refundForm.post(order.refund_url)">
    <h2 class="text-sm font-semibold">申请退款</h2>
    <p v-if="order.max_refund_label" class="text-xs text-muted-foreground">最多可退 {{ order.max_refund_label }}</p>
    <div class="space-y-2">
      <Label for="amount">退款金额（分）</Label>
      <Input id="amount" v-model.number="refundForm.amount_cents" type="number" min="1" :max="order.max_refund_cents" required />
    </div>
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
    <Button v-else-if="order.can_confirm_free" type="button" @click="payForm.post(routes.storeCheckout)">确认订单</Button>
    <Button v-else-if="order.can_pay" type="button" @click="payForm.post(routes.storeCheckout)">支付</Button>
    <div v-if="order.can_cancel" class="flex flex-wrap items-end gap-2">
      <div class="space-y-1">
        <Label for="cancel_reason">取消原因（可选）</Label>
        <Input id="cancel_reason" v-model="cancelForm.reason" placeholder="例如：买错了 / 暂时不需要" class="w-64" />
      </div>
      <Button type="button" variant="outline" @click="cancelForm.post(order.cancel_url)">取消订单</Button>
    </div>
    <Button v-if="order.can_reorder && order.reorder_url" type="button" variant="outline" @click="reorderForm.post(order.reorder_url)">再次购买</Button>
    <Button v-if="order.can_download_receipt" as-child variant="outline">
      <a :href="order.receipt_url" target="_blank" rel="noopener">HTML 收据</a>
      <a v-if="order.packing_slip_url" :href="order.packing_slip_url" target="_blank" rel="noopener" class="ml-3">装箱单</a>
    </Button>
    <Button v-if="order.can_download_receipt" as-child variant="outline">
      <a :href="order.receipt_pdf_url">PDF 收据</a>
    </Button>
    <Button as-child variant="outline">
      <Link :href="routes.storeOrders">返回订单列表</Link>
    </Button>
  </div>
</template>
