<script setup lang="ts">
import { ref, onMounted, watch, computed } from 'vue'
import { Link, useForm } from '@inertiajs/vue3'
import { usePage } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Textarea from '@/components/ui/Textarea.vue'
import Table from '@/components/ui/Table.vue'
import TableBody from '@/components/ui/TableBody.vue'
import TableCell from '@/components/ui/TableCell.vue'
import TableHead from '@/components/ui/TableHead.vue'
import TableHeader from '@/components/ui/TableHeader.vue'
import TableRow from '@/components/ui/TableRow.vue'
import Select from '@/components/ui/Select.vue'
import Checkbox from '@/components/ui/Checkbox.vue'
import Radio from '@/components/ui/Radio.vue'
import { useI18n } from 'vue-i18n'
import { routes } from '@/lib/routes'
import { resolveStoreFeatures } from '@/lib/storeFeatures'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()
const page = usePage()
const storeFeatures = computed(() =>
  resolveStoreFeatures(page.props.storeFeatures as Parameters<typeof resolveStoreFeatures>[0]),
)

const showShipping = computed(() => storeFeatures.value.shipping && props.requiresShipping)
const showGiftWrap = computed(() => storeFeatures.value.gift_wrap && props.giftWrapAvailable)

export interface CheckoutItem {
  product_name: string
  variant_name?: string | null
  quantity: number
  total_label: string
}

export interface ProviderOption {
  value: string
  label: string
}

const props = defineProps<{
  items: CheckoutItem[]
  subtotalCents: number
  subtotalLabel: string
  providers: ProviderOption[]
  defaultProvider?: string
  pendingCouponCode?: string | null
  pendingGiftCardCode?: string | null
  couponAutoApplied?: boolean
  requiresShipping?: boolean
  defaultShippingAddress?: {
    name: string
    phone: string
    line1: string
    line2: string
    city: string
    province: string
    postal_code: string
  } | null
  savedAddresses?: Array<{
    id: number
    label: string | null
    summary: string
    address: {
      name: string
      phone: string
      line1: string
      line2: string
      city: string
      province: string
      postal_code: string
    }
  }>
  shippingAddressesUrl?: string
  shippingLabel?: string | null
  freeShipping?: boolean
  shippingMethods?: Array<{ code: string; label: string; cents: number; delivery_estimate?: string | null; label_with_price: string }>
  shippingMethodCode?: string | null
  freeShippingMinLabel?: string | null
  freeShippingRemainingLabel?: string | null
  giftWrapAvailable?: boolean
  giftWrapCents?: number
  giftWrapLabel?: string
  minCheckoutCents?: number
  minCheckoutLabel?: string | null
  belowMinCheckout?: boolean
  previewCouponUrl: string
  previewGiftCardUrl: string
  storeCreditBalanceCents?: number
  storeCreditBalanceLabel?: string | null
  previewStoreCreditUrl?: string
}>()

const form = useForm({
  checkout: {
    provider: props.defaultProvider || props.providers[0]?.value || 'fake',
    coupon_code: props.pendingCouponCode || '',
    gift_card_code: props.pendingGiftCardCode || '',
    notes: '',
    shipping_method: props.shippingMethodCode || props.shippingMethods?.[0]?.code || 'standard',
    gift_wrap: false,
    use_store_credit: true,
    shipping_address: {
      name: props.defaultShippingAddress?.name || '',
      phone: props.defaultShippingAddress?.phone || '',
      line1: props.defaultShippingAddress?.line1 || '',
      line2: props.defaultShippingAddress?.line2 || '',
      city: props.defaultShippingAddress?.city || '',
      province: props.defaultShippingAddress?.province || '',
      postal_code: props.defaultShippingAddress?.postal_code || '',
    },
  },
})

const couponMessage = ref<string | null>(null)
const couponError = ref<string | null>(null)
const couponMinAmountHint = ref<string | null>(null)
const couponRemainingHint = ref<string | null>(null)
const giftCardMessage = ref<string | null>(null)
const giftCardError = ref<string | null>(null)
const discountLabel = ref<string | null>(null)
const giftCardLabel = ref<string | null>(null)
const storeCreditLabel = ref<string | null>(null)
const totalLabel = ref<string | null>(props.subtotalLabel)
const previewing = ref(false)
const previewingGiftCard = ref(false)
const selectedAddressId = ref<number | ''>('')

const savedAddressOptions = computed(() => [
  { value: '', label: t('commerce.checkout.manualEntry') },
  ...(props.savedAddresses || []).map((saved) => ({
    value: String(saved.id),
    label: `${saved.summary}${saved.label ? `（${saved.label}）` : ''}`,
  })),
])

const providerOptions = computed(() =>
  props.providers.map((provider) => ({ value: provider.value, label: provider.label })),
)

function updateSelectedAddressId(value: string) {
  selectedAddressId.value = value ? Number(value) : ''
}

function updateUseStoreCredit(value: boolean) {
  form.checkout.use_store_credit = value
  void refreshStoreCredit()
}

const selectedShippingEstimate = computed(() => {
  const method = props.shippingMethods?.find((item) => item.code === form.checkout.shipping_method)
  return method?.delivery_estimate ?? null
})

function applySavedAddress(id: number | '') {
  if (!id) return
  const saved = props.savedAddresses?.find((entry) => entry.id === id)
  if (!saved) return
  const address = saved.address
  form.checkout.shipping_address.name = address.name
  form.checkout.shipping_address.phone = address.phone
  form.checkout.shipping_address.line1 = address.line1
  form.checkout.shipping_address.line2 = address.line2
  form.checkout.shipping_address.city = address.city
  form.checkout.shipping_address.province = address.province
  form.checkout.shipping_address.postal_code = address.postal_code
}

watch(selectedAddressId, (id) => {
  if (id) applySavedAddress(id)
})

watch(() => form.checkout.gift_wrap, async () => {
  if (form.checkout.gift_card_code.trim()) {
    await previewGiftCard()
  } else if (form.checkout.coupon_code.trim()) {
    await previewCoupon()
  } else {
    await refreshStoreCredit()
  }
})

async function refreshStoreCredit() {
  storeCreditLabel.value = null
  if (!props.previewStoreCreditUrl || !form.checkout.use_store_credit) return
  if (!props.storeCreditBalanceCents) return

  try {
    const response = await fetch(props.previewStoreCreditUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content || '',
      },
      body: JSON.stringify({
        gift_wrap: form.checkout.gift_wrap,
      }),
    })
    const data = await response.json()
    if (response.ok && data.store_credit_amount_cents > 0) {
      storeCreditLabel.value = data.store_credit_amount_label
      totalLabel.value = data.total_label
    }
  } catch {
    // ignore preview errors
  }
}

async function previewGiftCard() {
  giftCardMessage.value = null
  giftCardError.value = null
  giftCardLabel.value = null
  if (!totalLabel.value) totalLabel.value = props.subtotalLabel

  if (!form.checkout.gift_card_code.trim()) return

  previewingGiftCard.value = true
  try {
    const response = await fetch(props.previewGiftCardUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content || '',
      },
      body: JSON.stringify({
        code: form.checkout.gift_card_code,
        coupon_code: form.checkout.coupon_code,
        gift_wrap: form.checkout.gift_wrap,
      }),
    })
    const data = await response.json()
    if (response.ok) {
      giftCardMessage.value = t('commerce.checkout.giftCardApplied', { code: data.code })
      giftCardLabel.value = data.gift_card_amount_label
      totalLabel.value = data.total_label
      await refreshStoreCredit()
    } else {
      giftCardError.value = data.error || t('commerce.checkout.invalidGiftCard')
    }
  } catch {
    giftCardError.value = t('commerce.checkout.giftCardVerifyFailed')
  } finally {
    previewingGiftCard.value = false
  }
}

async function previewCoupon() {
  couponMessage.value = null
  couponError.value = null
  couponMinAmountHint.value = null
  couponRemainingHint.value = null
  discountLabel.value = null
  totalLabel.value = props.subtotalLabel

  if (!form.checkout.coupon_code.trim()) return

  previewing.value = true
  try {
    const response = await fetch(props.previewCouponUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content || '',
      },
      body: JSON.stringify({
        code: form.checkout.coupon_code,
        gift_wrap: form.checkout.gift_wrap,
      }),
    })
    const data = await response.json()
    if (response.ok) {
      couponMessage.value = t('commerce.checkout.couponApplied', { code: data.code })
      discountLabel.value = data.discount_label
      totalLabel.value = data.total_label
      couponMinAmountHint.value = data.min_amount_label ? t('commerce.checkout.minSpend', { amount: data.min_amount_label }) : null
      couponRemainingHint.value = data.amount_remaining_label ? t('commerce.checkout.amountRemaining', { amount: data.amount_remaining_label }) : null
      if (form.checkout.gift_card_code.trim()) {
        await previewGiftCard()
      } else {
        await refreshStoreCredit()
      }
    } else {
      couponError.value = data.error || t('commerce.checkout.invalidCoupon')
    }
  } catch {
    couponError.value = t('commerce.checkout.couponVerifyFailed')
  } finally {
    previewing.value = false
  }
}

onMounted(() => {
  if (props.pendingCouponCode) {
    previewCoupon()
  } else if (props.pendingGiftCardCode) {
    previewGiftCard()
  } else {
    refreshStoreCredit()
  }
})
</script>

<template>
  <PageHeader :title="t('commerce.checkout.title')" />

  <p v-if="belowMinCheckout && minCheckoutLabel" class="mb-4 rounded-md border border-amber-300 bg-amber-50 px-4 py-3 text-sm text-amber-900">
    {{ t('commerce.checkout.belowMinCheckout', { amount: minCheckoutLabel }) }}
  </p>

  <div v-if="items.length" class="max-w-2xl space-y-6">
    <div class="rounded-lg border">
      <Table>
        <TableHeader><TableRow><TableHead>{{ t('commerce.checkout.product') }}</TableHead><TableHead>{{ t('commerce.checkout.quantity') }}</TableHead><TableHead>{{ t('commerce.checkout.lineTotal') }}</TableHead></TableRow></TableHeader>
        <TableBody>
          <TableRow v-for="(item, index) in items" :key="index">
            <TableCell>
              {{ item.product_name }}
              <span v-if="item.variant_name" class="ml-1 text-xs text-muted-foreground">({{ item.variant_name }})</span>
            </TableCell>
            <TableCell>{{ item.quantity }}</TableCell>
            <TableCell>{{ item.total_label }}</TableCell>
          </TableRow>
        </TableBody>
      </Table>
    </div>

    <div class="space-y-1 text-sm">
      <p>{{ t('commerce.checkout.subtotal', { amount: subtotalLabel }) }}</p>
      <p v-if="storeFeatures.shipping && shippingLabel">{{ t('commerce.checkout.shipping', { amount: freeShipping ? t('commerce.checkout.freeShipping') : shippingLabel }) }}</p>
      <p v-if="storeFeatures.shipping && freeShippingRemainingLabel" class="text-xs text-amber-600">{{ t('commerce.checkout.freeShippingRemaining', { remaining: freeShippingRemainingLabel }) }}</p>
      <p v-if="discountLabel" class="text-green-600">{{ t('commerce.checkout.discount', { amount: discountLabel }) }}</p>
      <p v-if="giftCardLabel" class="text-green-600">{{ t('commerce.checkout.giftCard', { amount: giftCardLabel }) }}</p>
      <p v-if="storeCreditBalanceLabel" class="text-muted-foreground">{{ t('commerce.checkout.storeCreditBalance', { amount: storeCreditBalanceLabel }) }}</p>
      <p v-if="storeCreditLabel" class="text-green-600">{{ t('commerce.checkout.storeCreditApplied', { amount: storeCreditLabel }) }}</p>
      <p class="font-medium">{{ t('commerce.checkout.total', { amount: totalLabel }) }}</p>
    </div>

    <label v-if="storeCreditBalanceCents" class="flex items-center gap-2 text-sm">
      <Checkbox
        :model-value="form.checkout.use_store_credit"
        @update:model-value="updateUseStoreCredit"
      />
      {{ t('commerce.checkout.useStoreCredit') }}
    </label>

    <p v-if="couponAutoApplied && pendingCouponCode" class="text-sm text-green-700">
      {{ t('commerce.checkout.couponAutoApplied', { code: pendingCouponCode }) }}
    </p>

    <form class="space-y-4" @submit.prevent="form.post(routes.storeCheckout)">
      <div class="space-y-2">
        <Label for="coupon">{{ t('commerce.checkout.coupon') }}</Label>
        <div class="flex gap-2">
          <Input id="coupon" v-model="form.checkout.coupon_code" :placeholder="t('commerce.checkout.couponPlaceholder')" class="flex-1" />
          <Button type="button" variant="outline" :disabled="previewing" @click="previewCoupon">{{ t('commerce.checkout.validate') }}</Button>
        </div>
        <p v-if="couponMessage" class="text-sm text-green-600">{{ couponMessage }}</p>
        <p v-if="couponMinAmountHint" class="text-xs text-muted-foreground">{{ couponMinAmountHint }}</p>
        <p v-if="couponRemainingHint" class="text-xs text-amber-600">{{ couponRemainingHint }}</p>
        <p v-if="couponError" class="text-sm text-destructive">{{ couponError }}</p>
      </div>

      <div class="space-y-2">
        <Label for="gift_card">{{ t('commerce.checkout.giftCardLabel') }}</Label>
        <div class="flex gap-2">
          <Input id="gift_card" v-model="form.checkout.gift_card_code" :placeholder="t('commerce.checkout.giftCardPlaceholder')" class="flex-1" />
          <Button type="button" variant="outline" :disabled="previewingGiftCard" @click="previewGiftCard">{{ t('commerce.checkout.validate') }}</Button>
        </div>
        <p v-if="giftCardMessage" class="text-sm text-green-600">{{ giftCardMessage }}</p>
        <p v-if="giftCardError" class="text-sm text-destructive">{{ giftCardError }}</p>
      </div>

      <div v-if="showShipping && shippingMethods?.length" class="space-y-2 rounded-lg border p-4">
        <p class="text-sm font-medium">{{ t('commerce.checkout.shippingMethods') }}</p>
        <label v-for="method in shippingMethods" :key="method.code" class="flex cursor-pointer items-center gap-2 text-sm">
          <Radio v-model="form.checkout.shipping_method" name="shipping_method" :value="method.code" />
          {{ method.label_with_price }}
        </label>
        <p v-if="selectedShippingEstimate" class="text-xs text-muted-foreground">
          {{ t('commerce.checkout.deliveryEstimate', { estimate: selectedShippingEstimate }) }}
        </p>
      </div>
      <div v-if="showShipping" class="space-y-3 rounded-lg border p-4">
        <div class="flex flex-wrap items-center justify-between gap-2">
          <h2 class="text-sm font-semibold">{{ t('commerce.checkout.shippingAddress') }}</h2>
          <Link v-if="shippingAddressesUrl" :href="shippingAddressesUrl" class="text-xs text-primary hover:underline">{{ t('commerce.checkout.manageAddresses') }}</Link>
        </div>
        <div v-if="savedAddresses?.length" class="space-y-2">
          <Label for="saved_address">{{ t('commerce.checkout.savedAddress') }}</Label>
          <Select
            id="saved_address"
            :model-value="selectedAddressId === '' ? '' : String(selectedAddressId)"
            :options="savedAddressOptions"
            block
            @update:model-value="updateSelectedAddressId"
          />
        </div>
        <div class="grid gap-3 sm:grid-cols-2">
          <div class="space-y-2">
            <Label for="ship_name">{{ t('commerce.checkout.recipient') }}</Label>
            <Input id="ship_name" v-model="form.checkout.shipping_address.name" required />
          </div>
          <div class="space-y-2">
            <Label for="ship_phone">{{ t('commerce.checkout.phone') }}</Label>
            <Input id="ship_phone" v-model="form.checkout.shipping_address.phone" required />
          </div>
        </div>
        <div class="space-y-2">
          <Label for="ship_line1">{{ t('commerce.checkout.address') }}</Label>
          <Input id="ship_line1" v-model="form.checkout.shipping_address.line1" required />
        </div>
        <div class="space-y-2">
          <Label for="ship_line2">{{ t('commerce.checkout.addressLine2') }}</Label>
          <Input id="ship_line2" v-model="form.checkout.shipping_address.line2" />
        </div>
        <div class="grid gap-3 sm:grid-cols-3">
          <div class="space-y-2">
            <Label for="ship_province">{{ t('commerce.checkout.province') }}</Label>
            <Input id="ship_province" v-model="form.checkout.shipping_address.province" required />
          </div>
          <div class="space-y-2">
            <Label for="ship_city">{{ t('commerce.checkout.city') }}</Label>
            <Input id="ship_city" v-model="form.checkout.shipping_address.city" required />
          </div>
          <div class="space-y-2">
            <Label for="ship_postal">{{ t('commerce.checkout.postalCode') }}</Label>
            <Input id="ship_postal" v-model="form.checkout.shipping_address.postal_code" />
          </div>
        </div>
      </div>

      <label v-if="showGiftWrap" class="flex items-center gap-2 rounded-lg border p-4 text-sm">
        <Checkbox v-model="form.checkout.gift_wrap" />
        {{ t('commerce.checkout.giftWrap', { label: giftWrapLabel }) }}
      </label>

      <div class="space-y-2">
        <Label for="notes">{{ t('commerce.checkout.notes') }}</Label>
        <Textarea id="notes" v-model="form.checkout.notes" rows="2" :placeholder="t('commerce.checkout.notesPlaceholder')" />
      </div>

      <div class="space-y-2">
        <Label for="provider">{{ t('commerce.checkout.paymentMethod') }}</Label>
        <Select id="provider" v-model="form.checkout.provider" :options="providerOptions" block />
      </div>
      <Button type="submit" :disabled="form.processing || belowMinCheckout">{{ t('commerce.checkout.payNow') }}</Button>
    </form>
  </div>

  <div v-else class="space-y-4">
    <p class="text-sm text-muted-foreground">{{ t('commerce.checkout.emptyCart') }}</p>
    <Button as-child variant="outline">
      <Link :href="routes.storeCart">{{ t('commerce.checkout.viewCart') }}</Link>
    </Button>
  </div>
</template>
