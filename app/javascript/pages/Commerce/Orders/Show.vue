<script setup lang="ts">
import { ref, onMounted, onUnmounted, computed } from 'vue'
import { Link, router, useForm, usePage } from '@inertiajs/vue3'
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
import Select from '@/components/ui/Select.vue'
import { useI18n } from 'vue-i18n'
import { routes } from '@/lib/routes'
import { resolveStoreFeatures } from '@/lib/storeFeatures'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()
const page = usePage()
const storeFeatures = computed(() =>
  resolveStoreFeatures(page.props.storeFeatures as Parameters<typeof resolveStoreFeatures>[0]),
)

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
      fulfillment_error?: string | null
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
      last_error?: string | null
    }>
  }
}>()

const payForm = useForm({
  order_id: props.order.id,
  checkout: { provider: props.order.default_provider || 'fake' },
})

const paymentProviderOptions = computed(() =>
  props.order.payment_providers.map((provider) => ({ value: provider.value, label: provider.label })),
)

const order = computed(() => page.props.order as typeof props.order)

const isFulfilling = computed(() => ['processing', 'fulfilling'].includes(order.value.status))

const hasFailedFulfillment = computed(() =>
  order.value.fulfillments.some((f) => f.status === 'failed')
  || order.value.items.some((item) => item.fulfillment_status === 'failed'),
)

function fulfillmentBadgeVariant(status: string | null | undefined) {
  if (status === 'fulfilled') return 'success'
  if (status === 'failed') return 'danger'
  return 'default'
}

const cancelForm = useForm({ reason: '' })
const refundForm = useForm({ reason: '', amount_cents: 0 as number | '' })

const statusSubtitle = computed(() => {
  if (isFulfilling.value) {
    return t('commerce.orderShow.fulfillmentPending', { status: order.value.status_label })
  }
  if (order.value.status === 'paid') {
    return t('commerce.orderShow.paidPendingFulfillment', { status: order.value.status_label })
  }
  if (order.value.status === 'completed') {
    return t('commerce.orderShow.statusSubtitleCompleted', { status: order.value.status_label })
  }
  return t('commerce.orderShow.statusSubtitle', { status: order.value.status_label })
})

let pollTimer: ReturnType<typeof setInterval> | null = null
let pollStopTimer: ReturnType<typeof setTimeout> | null = null

function stopStatusPolling() {
  if (pollTimer) {
    clearInterval(pollTimer)
    pollTimer = null
  }
  if (pollStopTimer) {
    clearTimeout(pollStopTimer)
    pollStopTimer = null
  }
}

function startStatusPolling() {
  stopStatusPolling()
  if (!isFulfilling.value) return

  pollTimer = setInterval(() => {
    const current = page.props.order as typeof props.order
    if (!['processing', 'fulfilling'].includes(current.status)) {
      stopStatusPolling()
      return
    }
    router.reload({ only: ['order'], preserveScroll: true, preserveState: true })
  }, 4000)
  pollStopTimer = setTimeout(stopStatusPolling, 120_000)
}

onMounted(() => {
  if (props.order.max_refund_cents) {
    refundForm.amount_cents = props.order.max_refund_cents
  }
  startStatusPolling()
})

onUnmounted(stopStatusPolling)
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
  <PageHeader
    :title="t('commerce.orderShow.title', { number: order.order_number })"
    :subtitle="statusSubtitle"
  />

  <p v-if="isFulfilling" class="mb-4 rounded-md border border-amber-300 bg-amber-50 px-4 py-3 text-sm text-amber-900">
    {{ t('commerce.orderShow.fulfillmentPollingHint') }}
  </p>

  <p v-if="hasFailedFulfillment" class="mb-4 rounded-md border border-red-300 bg-red-50 px-4 py-3 text-sm text-red-900">
    {{ t('commerce.orderShow.fulfillmentFailedHint') }}
  </p>

  <p v-if="order.notes" class="mb-4 rounded-lg border p-4 text-sm">
    <span class="font-medium">{{ t('commerce.orderShow.orderNotes') }}</span>{{ order.notes }}
  </p>

  <p v-if="storeFeatures.shipping && order.shipping_address_label" class="mb-4 rounded-lg border p-4 text-sm">
    <span class="font-medium">{{ t('commerce.orderShow.shippingAddress') }}</span>{{ order.shipping_address_label }}
    <span v-if="order.shipping_method_label" class="mt-1 block text-muted-foreground">{{ t('commerce.orderShow.shippingMethod', { method: order.shipping_method_label }) }}</span>
  </p>
  <p v-if="storeFeatures.order_shipping_management && order.tracking_number" class="mb-4 rounded-lg border p-4 text-sm">
    <span class="font-medium">{{ t('commerce.orderShow.trackingInfo') }}</span>
    {{ order.shipping_carrier || t('commerce.orderShow.defaultCarrier') }} — {{ order.tracking_number }}
    <span v-if="order.shipped_at" class="text-muted-foreground">{{ t('commerce.orderShow.shippedAt', { at: order.shipped_at }) }}</span>
    <span v-if="order.delivery_estimate" class="text-muted-foreground"> · {{ order.delivery_estimate }}</span>
    <a v-if="order.tracking_url" :href="order.tracking_url" target="_blank" rel="noopener" class="ml-2 text-primary hover:underline">{{ t('commerce.orderShow.trackShipment') }}</a>
  </p>

  <div v-if="storeFeatures.order_shipping_management && order.shipping_timeline?.length" class="mb-6 rounded-lg border p-4">
    <h2 class="mb-4 text-sm font-semibold">{{ t('commerce.orderShow.shippingTimeline') }}</h2>
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
    {{ t('commerce.orderShow.payBefore', { expires: order.payment_expires_label }) }}
  </p>
  <p v-else-if="order.payment_expired" class="mb-4 rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-900">
    {{ t('commerce.orderShow.paymentExpired', { expires: order.payment_expires_label }) }}
  </p>

  <p v-if="order.refund_window_expires_label && order.can_request_refund" class="mb-4 rounded-lg border border-blue-200 bg-blue-50 px-4 py-3 text-sm text-blue-900">
    {{ t('commerce.orderShow.refundWindowCloses', { expires: order.refund_window_expires_label }) }}
  </p>
  <p v-else-if="order.refund_window_expires_label && !order.can_request_refund && order.status === 'paid'" class="mb-4 rounded-lg border px-4 py-3 text-sm text-muted-foreground">
    {{ t('commerce.orderShow.refundWindowClosed', { expires: order.refund_window_expires_label }) }}
  </p>

  <p v-if="order.refund_pending" class="mb-4 rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
    {{ t('commerce.orderShow.refundPending') }}
  </p>

  <div v-if="order.downloads?.length" class="mb-6">
    <h2 class="mb-4 flex items-center gap-2 text-base font-semibold">
      <span class="flex h-7 w-7 items-center justify-center rounded-lg bg-primary/10 text-primary text-sm">↓</span>
      {{ t('commerce.orderShow.digitalDownloads') }}
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
          <p class="mt-0.5 text-xs text-muted-foreground">{{ t('commerce.orderShow.clickToDownload') }}</p>
        </div>
        <span class="text-sm text-primary opacity-0 transition-opacity group-hover:opacity-100">→</span>
      </a>
    </div>
  </div>

  <div v-if="order.events.length" class="mb-6 rounded-lg border p-4">
    <h2 class="mb-3 text-sm font-semibold">{{ t('commerce.orderShow.timeline') }}</h2>
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
          <TableHead>{{ t('commerce.orderShow.product') }}</TableHead>
          <TableHead>{{ t('commerce.orderShow.quantity') }}</TableHead>
          <TableHead>{{ t('commerce.orderShow.lineTotal') }}</TableHead>
          <TableHead>{{ t('commerce.orderShow.fulfillment') }}</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        <TableRow v-for="(item, index) in order.items" :key="index">
          <TableCell>
            <Link v-if="item.product_url" :href="item.product_url" class="hover:underline">{{ item.product_name }}</Link>
            <template v-else>{{ item.product_name }}</template>
            <span v-if="item.variant_name" class="text-muted-foreground"> — {{ item.variant_name }}</span>
            <p v-if="item.gift_note" class="mt-1 text-xs text-muted-foreground">{{ t('commerce.orderShow.giftNote', { note: item.gift_note }) }}</p>
            <div v-if="item.ask_question_url || item.discussion_url" class="mt-1 flex gap-2">
              <Link v-if="item.discussion_url" :href="item.discussion_url" class="text-xs text-primary hover:underline">{{ t('commerce.orderShow.joinDiscussion') }}</Link>
            </div>
            <div v-if="item.product_public_id && item.id" class="mt-2 space-y-2">
              <div v-for="q in item.questions || []" :key="q.id" class="rounded border bg-muted/30 p-2 text-xs">
                <p class="font-medium">{{ t('commerce.orderShow.questionPrefix') }} {{ q.body }}</p>
                <p v-for="(a, ai) in q.answers" :key="ai" class="mt-1 text-muted-foreground">
                  {{ t('commerce.orderShow.officialAnswer', { author: a.official ? t('commerce.orderShow.official') : a.author, body: a.body }) }}
                </p>
              </div>
              <div class="flex gap-2">
                <Textarea v-model="questionForms[item.id]" rows="2" :placeholder="t('commerce.orderShow.askQuestionPlaceholder')" class="text-xs" />
                <Button type="button" size="sm" variant="outline" @click="submitItemQuestion(item)">{{ t('commerce.orderShow.askQuestion') }}</Button>
              </div>
            </div>
            <ul v-if="item.issued_gift_cards?.length" class="mt-2 space-y-1 text-xs text-green-700">
              <li v-for="card in item.issued_gift_cards" :key="card.code">
                {{ t('commerce.orderShow.giftCardPrefix') }}
                <Link :href="card.url" class="font-mono underline">{{ card.code }}</Link>（{{ card.balance_label }}）
              </li>
            </ul>
          </TableCell>
          <TableCell>{{ item.quantity }}</TableCell>
          <TableCell>{{ item.total_label }}</TableCell>
          <TableCell>
            <Badge v-if="item.fulfillment_status_label || item.fulfillment_status" :variant="fulfillmentBadgeVariant(item.fulfillment_status)">
              {{ item.fulfillment_status_label || item.fulfillment_status }}
            </Badge>
            <p v-if="item.fulfillment_error" class="mt-1 text-xs text-red-600">
              {{ t('commerce.orderShow.fulfillmentFailed', { error: item.fulfillment_error }) }}
            </p>
            <a
              v-if="item.download_url"
              :href="item.download_url"
              target="_blank"
              rel="noopener"
              class="ml-2 inline-flex items-center gap-1 rounded-md bg-primary/10 px-2 py-0.5 text-xs font-medium text-primary transition-colors no-underline hover:bg-primary/20"
            >
              ⬇ {{ t('commerce.orderShow.download') }}
            </a>
            <Button
              v-if="item.refresh_download_url"
              type="button"
              variant="ghost"
              size="sm"
              class="ml-1 h-auto px-1 text-xs"
              @click="refreshDownload(item.refresh_download_url!)"
            >
              {{ t('commerce.orderShow.refreshLink') }}
            </Button>
            <span v-else-if="!item.fulfillment_status" class="text-muted-foreground">—</span>
          </TableCell>
        </TableRow>
      </TableBody>
    </Table>
  </div>

  <div v-if="order.customer_notes?.length" class="mb-6 rounded-lg border p-4">
    <h2 class="mb-3 text-sm font-semibold">{{ t('commerce.orderShow.merchantNotes') }}</h2>
    <ul class="space-y-2 text-sm">
      <li v-for="(note, index) in order.customer_notes" :key="index">
        <p>{{ note.body }}</p>
        <p class="mt-1 text-xs text-muted-foreground">{{ note.author }} · {{ note.created_at }}</p>
      </li>
    </ul>
  </div>

  <div v-if="order.fulfillments.length" class="mb-6 rounded-lg border p-4">
    <h2 class="mb-3 text-sm font-semibold">{{ t('commerce.orderShow.fulfillments') }}</h2>
    <ul class="space-y-2 text-sm">
      <li v-for="fulfillment in order.fulfillments" :key="fulfillment.delivery_id" class="flex justify-between gap-4">
        <code class="text-xs">{{ fulfillment.delivery_id }}</code>
        <span>
          <Badge :variant="fulfillmentBadgeVariant(fulfillment.status)">{{ fulfillment.status_label || fulfillment.status }}</Badge>
          <span v-if="fulfillment.last_error" class="ml-2 text-xs text-red-600">
            {{ t('commerce.orderShow.fulfillmentFailed', { error: fulfillment.last_error }) }}
          </span>
          <span v-if="fulfillment.fulfilled_at" class="ml-2 text-muted-foreground">{{ fulfillment.fulfilled_at }}</span>
        </span>
      </li>
    </ul>
  </div>

  <div v-if="order.refunds.length" class="mb-6 rounded-lg border p-4">
    <h2 class="mb-3 text-sm font-semibold">{{ t('commerce.orderShow.refunds') }}</h2>
    <ul class="space-y-2 text-sm">
      <li v-for="(refund, index) in order.refunds" :key="index" class="flex justify-between gap-4">
        <span>{{ refund.amount_label }}</span>
        <span>
          <Badge>{{ refund.status_label || refund.status }}</Badge>
          <span v-if="refund.reason" class="ml-2 text-xs text-muted-foreground">{{ refund.reason }}</span>
          <span v-if="refund.customer_requested" class="ml-2 text-xs text-muted-foreground">{{ t('commerce.orderShow.customerRequested') }}</span>
          <span class="ml-2 text-muted-foreground">{{ refund.created_at }}</span>
        </span>
      </li>
    </ul>
  </div>

  <div v-if="order.restorations?.length" class="mb-6 rounded-lg border border-green-200 bg-green-50 p-4 dark:border-green-900 dark:bg-green-950">
    <h2 class="mb-3 text-sm font-semibold text-green-900 dark:text-green-100">{{ t('commerce.orderShow.restorationDetails') }}</h2>
    <ul class="space-y-1 text-sm text-green-800 dark:text-green-200">
      <li v-for="(item, index) in order.restorations" :key="index" class="flex justify-between gap-4">
        <span>{{ item.label }}</span>
        <span class="font-medium">{{ item.amount_label }}</span>
      </li>
    </ul>
  </div>

  <p v-if="order.subtotal_label" class="mb-1 text-sm text-muted-foreground">{{ t('commerce.orderShow.subtotal', { amount: order.subtotal_label }) }}</p>
  <p v-if="storeFeatures.shipping && order.shipping_label" class="mb-1 text-sm text-muted-foreground">{{ t('commerce.orderShow.shipping', { amount: order.free_shipping ? t('commerce.orderShow.freeShipping') : order.shipping_label }) }}</p>
  <p v-if="storeFeatures.gift_wrap && order.gift_wrap_label" class="mb-1 text-sm text-muted-foreground">{{ t('commerce.orderShow.giftWrap', { amount: order.gift_wrap_label }) }}</p>
  <p v-if="order.discount_label" class="mb-1 text-sm text-green-700">{{ t('commerce.orderShow.discount', { code: order.coupon_code ? ` (${order.coupon_code})` : '', amount: order.discount_label }) }}</p>
  <p v-if="order.gift_card_amount_label" class="mb-1 text-sm text-green-700">{{ t('commerce.orderShow.giftCardDiscount', { code: order.gift_card_code ? ` (${order.gift_card_code})` : '', amount: order.gift_card_amount_label }) }}</p>
  <p v-if="order.store_credit_amount_label" class="mb-1 text-sm text-green-700">{{ t('commerce.orderShow.storeCredit', { amount: order.store_credit_amount_label }) }}</p>
  <p class="mb-6 font-medium">{{ t('commerce.orderShow.total', { amount: order.total_label }) }}</p>

  <form v-if="order.can_request_refund" class="mb-6 max-w-md space-y-3 rounded-lg border p-4" @submit.prevent="refundForm.post(order.refund_url)">
    <h2 class="text-sm font-semibold">{{ t('commerce.orderShow.requestRefund') }}</h2>
    <p v-if="order.max_refund_label" class="text-xs text-muted-foreground">{{ t('commerce.orderShow.maxRefund', { amount: order.max_refund_label }) }}</p>
    <div class="space-y-2">
      <Label for="amount">{{ t('commerce.orderShow.refundAmountCents') }}</Label>
      <Input id="amount" v-model.number="refundForm.amount_cents" type="number" min="1" :max="order.max_refund_cents" required />
    </div>
    <div class="space-y-2">
      <Label for="reason">{{ t('commerce.orderShow.refundReason') }}</Label>
      <Textarea id="reason" v-model="refundForm.reason" rows="3" :placeholder="t('commerce.orderShow.refundReasonPlaceholder')" />
    </div>
    <Button type="submit" variant="outline" :disabled="refundForm.processing">{{ t('commerce.orderShow.submitRefund') }}</Button>
  </form>

  <div class="flex flex-wrap gap-3">
    <form v-if="order.can_pay && order.payment_providers.length > 1" class="flex items-center gap-2">
      <Select v-model="payForm.checkout.provider" :options="paymentProviderOptions" size="sm" />
      <Button type="button" @click="payForm.post(routes.storeCheckout)">{{ t('commerce.orderShow.pay') }}</Button>
    </form>
    <Button v-else-if="order.can_confirm_free" type="button" @click="payForm.post(routes.storeCheckout)">{{ t('commerce.orderShow.confirmOrder') }}</Button>
    <Button v-else-if="order.can_pay" type="button" @click="payForm.post(routes.storeCheckout)">{{ t('commerce.orderShow.pay') }}</Button>
    <div v-if="order.can_cancel" class="flex flex-wrap items-end gap-2">
      <div class="space-y-1">
        <Label for="cancel_reason">{{ t('commerce.orderShow.cancelReason') }}</Label>
        <Input id="cancel_reason" v-model="cancelForm.reason" :placeholder="t('commerce.orderShow.cancelReasonPlaceholder')" class="w-64" />
      </div>
      <Button type="button" variant="outline" @click="cancelForm.post(order.cancel_url)">{{ t('commerce.orderShow.cancelOrder') }}</Button>
    </div>
    <Button v-if="order.can_reorder && order.reorder_url" type="button" variant="outline" @click="reorderForm.post(order.reorder_url)">{{ t('commerce.orderShow.reorder') }}</Button>
    <Button v-if="order.can_download_receipt" as-child variant="outline">
      <a :href="order.receipt_url" target="_blank" rel="noopener">{{ t('commerce.orderShow.htmlReceipt') }}</a>
    </Button>
    <Button v-if="storeFeatures.order_shipping_management && order.packing_slip_url" as-child variant="outline">
      <a :href="order.packing_slip_url" target="_blank" rel="noopener">{{ t('commerce.orderShow.packingSlip') }}</a>
    </Button>
    <Button v-if="order.can_download_receipt" as-child variant="outline">
      <a :href="order.receipt_pdf_url">{{ t('commerce.orderShow.pdfReceipt') }}</a>
    </Button>
    <Button as-child variant="outline">
      <Link :href="routes.storeOrders">{{ t('commerce.orderShow.backToOrders') }}</Link>
    </Button>
  </div>
</template>
