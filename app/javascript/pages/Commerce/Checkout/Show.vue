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
import Select from '@/components/ui/Select.vue'
import Checkbox from '@/components/ui/Checkbox.vue'
import Radio from '@/components/ui/Radio.vue'
import { useI18n } from 'vue-i18n'
import { routes } from '@/lib/routes'
import { resolveStoreFeatures } from '@/lib/storeFeatures'
import { postJson, HttpError } from '@/lib/http'

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
    const data = await postJson<{ store_credit_amount_cents: number; store_credit_amount_label: string; total_label: string }>(
      props.previewStoreCreditUrl,
      { gift_wrap: form.checkout.gift_wrap },
    )
    if (data.store_credit_amount_cents > 0) {
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
    const data = await postJson<{ code: string; gift_card_amount_label: string; total_label: string }>(
      props.previewGiftCardUrl,
      {
        code: form.checkout.gift_card_code,
        coupon_code: form.checkout.coupon_code,
        gift_wrap: form.checkout.gift_wrap,
      },
    )
    giftCardMessage.value = t('commerce.checkout.giftCardApplied', { code: data.code })
    giftCardLabel.value = data.gift_card_amount_label
    totalLabel.value = data.total_label
    await refreshStoreCredit()
  } catch (error) {
    if (error instanceof HttpError) {
      giftCardError.value = (error.body as { error?: string })?.error || t('commerce.checkout.invalidGiftCard')
    } else {
      giftCardError.value = t('commerce.checkout.giftCardVerifyFailed')
    }
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
    const data = await postJson<{
      code: string
      discount_label: string
      total_label: string
      min_amount_label?: string | null
      amount_remaining_label?: string | null
    }>(props.previewCouponUrl, {
      code: form.checkout.coupon_code,
      gift_wrap: form.checkout.gift_wrap,
    })
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
  } catch (error) {
    if (error instanceof HttpError) {
      couponError.value = (error.body as { error?: string })?.error || t('commerce.checkout.invalidCoupon')
    } else {
      couponError.value = t('commerce.checkout.couponVerifyFailed')
    }
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

  <p
    v-if="belowMinCheckout && minCheckoutLabel"
    role="alert"
    class="
      mb-4 rounded-xl border border-amber-500/30 bg-amber-500/10 px-4 py-3
      text-sm leading-6 text-amber-900 dark:text-amber-100
    "
  >
    {{ t('commerce.checkout.belowMinCheckout', { amount: minCheckoutLabel }) }}
  </p>

  <div
    v-if="items.length"
    class="grid gap-8 lg:grid-cols-[minmax(0,1fr)_22rem] lg:items-start"
  >
    <form
      id="checkout-form"
      class="min-w-0 overflow-hidden rounded-xl border border-border bg-card shadow-sm"
      @submit.prevent="form.post(routes.storeCheckout)"
    >
      <section class="space-y-5 p-4 sm:p-6" aria-labelledby="discount-codes-heading">
        <div class="space-y-1">
          <h2 id="discount-codes-heading" class="text-lg font-semibold">
            {{ t('commerce.checkout.discountCodes') }}
          </h2>
          <p
            v-if="couponAutoApplied && pendingCouponCode"
            role="status"
            class="text-sm text-green-700 dark:text-green-400"
          >
            {{ t('commerce.checkout.couponAutoApplied', { code: pendingCouponCode }) }}
          </p>
        </div>

        <div class="grid gap-6 md:grid-cols-2">
          <div class="space-y-3">
            <Label for="coupon">{{ t('commerce.checkout.coupon') }}</Label>
            <Input
              id="coupon"
              v-model="form.checkout.coupon_code"
              autocomplete="off"
              :placeholder="t('commerce.checkout.couponPlaceholder')"
              aria-describedby="checkout-coupon-status"
              :aria-invalid="!!couponError"
            />
            <Button
              type="button"
              variant="outline"
              :disabled="previewing || !form.checkout.coupon_code.trim()"
              :aria-busy="previewing"
              @click="previewCoupon"
            >
              {{ previewing ? t('commerce.checkout.validating') : t('commerce.checkout.validate') }}
            </Button>
            <div id="checkout-coupon-status" aria-live="polite" class="space-y-1">
              <p v-if="couponMessage" class="text-sm text-green-600 dark:text-green-400">
                {{ couponMessage }}
              </p>
              <p v-if="couponMinAmountHint" class="text-xs leading-5 text-muted-foreground">
                {{ couponMinAmountHint }}
              </p>
              <p
                v-if="couponRemainingHint"
                class="text-xs leading-5 text-amber-600 dark:text-amber-400"
              >
                {{ couponRemainingHint }}
              </p>
              <p v-if="couponError" role="alert" class="text-sm text-destructive">{{ couponError }}</p>
            </div>
          </div>

          <div class="space-y-3">
            <Label for="gift_card">{{ t('commerce.checkout.giftCardLabel') }}</Label>
            <Input
              id="gift_card"
              v-model="form.checkout.gift_card_code"
              autocomplete="off"
              :placeholder="t('commerce.checkout.giftCardPlaceholder')"
              aria-describedby="checkout-gift-card-status"
              :aria-invalid="!!giftCardError"
            />
            <Button
              type="button"
              variant="outline"
              :disabled="previewingGiftCard || !form.checkout.gift_card_code.trim()"
              :aria-busy="previewingGiftCard"
              @click="previewGiftCard"
            >
              {{ previewingGiftCard ? t('commerce.checkout.validating') : t('commerce.checkout.validate') }}
            </Button>
            <div id="checkout-gift-card-status" aria-live="polite" class="space-y-1">
              <p v-if="giftCardMessage" class="text-sm text-green-600 dark:text-green-400">
                {{ giftCardMessage }}
              </p>
              <p v-if="giftCardError" role="alert" class="text-sm text-destructive">{{ giftCardError }}</p>
            </div>
          </div>
        </div>
      </section>

      <fieldset
        v-if="showShipping && shippingMethods?.length"
        class="space-y-4 border-t border-border p-4 sm:p-6"
      >
        <legend class="sr-only">{{ t('commerce.checkout.shippingMethods') }}</legend>
        <h2 class="text-lg font-semibold">{{ t('commerce.checkout.shippingMethods') }}</h2>
        <div class="space-y-1">
          <label
            v-for="method in shippingMethods"
            :key="method.code"
            class="flex cursor-pointer items-start gap-3 rounded-lg px-3 py-3 text-sm transition-colors"
            :class="
              form.checkout.shipping_method === method.code
                ? 'bg-primary/10 text-foreground'
                : 'hover:bg-muted/60'
            "
          >
            <Radio
              v-model="form.checkout.shipping_method"
              name="shipping_method"
              :value="method.code"
              class="mt-0.5"
            />
            <span class="min-w-0 flex-1">{{ method.label_with_price }}</span>
          </label>
        </div>
        <p v-if="selectedShippingEstimate" class="text-sm text-muted-foreground">
          {{ t('commerce.checkout.deliveryEstimate', { estimate: selectedShippingEstimate }) }}
        </p>
      </fieldset>

      <section
        v-if="showShipping"
        class="space-y-5 border-t border-border p-4 sm:p-6"
        aria-labelledby="shipping-address-heading"
      >
        <div class="flex flex-wrap items-center justify-between gap-3">
          <h2 id="shipping-address-heading" class="text-lg font-semibold">
            {{ t('commerce.checkout.shippingAddress') }}
          </h2>
          <Link
            v-if="shippingAddressesUrl"
            :href="shippingAddressesUrl"
            class="
              rounded-sm text-sm font-medium text-primary underline-offset-4
              hover:underline focus-visible:outline-none focus-visible:ring-2
              focus-visible:ring-ring
            "
          >
            {{ t('commerce.checkout.manageAddresses') }}
          </Link>
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

        <div class="grid gap-4 sm:grid-cols-2">
          <div class="space-y-2">
            <Label for="ship_name">{{ t('commerce.checkout.recipient') }}</Label>
            <Input
              id="ship_name"
              v-model="form.checkout.shipping_address.name"
              autocomplete="name"
              required
            />
          </div>
          <div class="space-y-2">
            <Label for="ship_phone">{{ t('commerce.checkout.phone') }}</Label>
            <Input
              id="ship_phone"
              v-model="form.checkout.shipping_address.phone"
              type="tel"
              autocomplete="tel"
              required
            />
          </div>
        </div>

        <div class="space-y-2">
          <Label for="ship_line1">{{ t('commerce.checkout.address') }}</Label>
          <Input
            id="ship_line1"
            v-model="form.checkout.shipping_address.line1"
            autocomplete="address-line1"
            required
          />
        </div>

        <div class="space-y-2">
          <Label for="ship_line2">{{ t('commerce.checkout.addressLine2') }}</Label>
          <Input
            id="ship_line2"
            v-model="form.checkout.shipping_address.line2"
            autocomplete="address-line2"
          />
        </div>

        <div class="grid gap-4 sm:grid-cols-3">
          <div class="space-y-2">
            <Label for="ship_province">{{ t('commerce.checkout.province') }}</Label>
            <Input
              id="ship_province"
              v-model="form.checkout.shipping_address.province"
              autocomplete="address-level1"
              required
            />
          </div>
          <div class="space-y-2">
            <Label for="ship_city">{{ t('commerce.checkout.city') }}</Label>
            <Input
              id="ship_city"
              v-model="form.checkout.shipping_address.city"
              autocomplete="address-level2"
              required
            />
          </div>
          <div class="space-y-2">
            <Label for="ship_postal">{{ t('commerce.checkout.postalCode') }}</Label>
            <Input
              id="ship_postal"
              v-model="form.checkout.shipping_address.postal_code"
              autocomplete="postal-code"
            />
          </div>
        </div>
      </section>

      <section
        class="space-y-5 border-t border-border p-4 sm:p-6"
        aria-labelledby="order-options-heading"
      >
        <h2 id="order-options-heading" class="text-lg font-semibold">
          {{ t('commerce.checkout.orderOptions') }}
        </h2>

        <div v-if="showGiftWrap" class="flex items-start gap-3 rounded-lg bg-muted/50 p-3">
          <Checkbox id="gift_wrap" v-model="form.checkout.gift_wrap" class="mt-0.5" />
          <Label for="gift_wrap" class="cursor-pointer leading-5">
            {{ t('commerce.checkout.giftWrap', { label: giftWrapLabel }) }}
          </Label>
        </div>

        <div class="space-y-2">
          <Label for="notes">{{ t('commerce.checkout.notes') }}</Label>
          <Textarea
            id="notes"
            v-model="form.checkout.notes"
            :rows="3"
            :placeholder="t('commerce.checkout.notesPlaceholder')"
          />
        </div>
      </section>

      <section
        class="space-y-3 border-t border-border p-4 sm:p-6"
        aria-labelledby="payment-method-heading"
      >
        <h2 id="payment-method-heading" class="text-lg font-semibold">
          {{ t('commerce.checkout.paymentMethod') }}
        </h2>
        <Label for="provider" class="sr-only">{{ t('commerce.checkout.paymentMethod') }}</Label>
        <Select id="provider" v-model="form.checkout.provider" :options="providerOptions" block />
      </section>
    </form>

    <aside class="lg:sticky lg:top-20">
      <section class="rounded-xl border border-border bg-card p-5 shadow-sm">
        <h2 class="text-base font-semibold">{{ t('commerce.checkout.orderSummary') }}</h2>

        <ul class="mt-4 divide-y border-y border-border">
          <li
            v-for="(item, index) in items"
            :key="index"
            class="flex items-start justify-between gap-4 py-3 text-sm"
          >
            <div class="min-w-0">
              <p class="font-medium leading-5">{{ item.product_name }}</p>
              <p v-if="item.variant_name" class="mt-0.5 text-xs leading-5 text-muted-foreground">
                {{ item.variant_name }}
              </p>
              <p class="mt-0.5 text-xs text-muted-foreground">
                {{ t('commerce.checkout.quantity') }} · {{ item.quantity }}
              </p>
            </div>
            <p class="shrink-0 font-medium tabular-nums">{{ item.total_label }}</p>
          </li>
        </ul>

        <div class="mt-4 space-y-2 text-sm leading-6">
          <p>{{ t('commerce.checkout.subtotal', { amount: subtotalLabel }) }}</p>
          <p v-if="storeFeatures.shipping && shippingLabel" class="text-muted-foreground">
            {{
              t('commerce.checkout.shipping', {
                amount: freeShipping ? t('commerce.checkout.freeShipping') : shippingLabel,
              })
            }}
          </p>
          <p
            v-if="storeFeatures.shipping && freeShippingRemainingLabel"
            class="text-xs text-amber-600 dark:text-amber-400"
          >
            {{ t('commerce.checkout.freeShippingRemaining', { remaining: freeShippingRemainingLabel }) }}
          </p>
          <p v-if="discountLabel" class="text-green-600 dark:text-green-400">
            {{ t('commerce.checkout.discount', { amount: discountLabel }) }}
          </p>
          <p v-if="giftCardLabel" class="text-green-600 dark:text-green-400">
            {{ t('commerce.checkout.giftCard', { amount: giftCardLabel }) }}
          </p>
          <p v-if="storeCreditBalanceLabel" class="text-muted-foreground">
            {{ t('commerce.checkout.storeCreditBalance', { amount: storeCreditBalanceLabel }) }}
          </p>
          <p v-if="storeCreditLabel" class="text-green-600 dark:text-green-400">
            {{ t('commerce.checkout.storeCreditApplied', { amount: storeCreditLabel }) }}
          </p>
          <p aria-live="polite" class="border-t border-border pt-3 text-base font-semibold">
            {{ t('commerce.checkout.total', { amount: totalLabel }) }}
          </p>
        </div>

        <div
          v-if="storeCreditBalanceCents"
          class="mt-4 flex items-start gap-3 rounded-lg bg-muted/50 p-3 text-sm leading-5"
        >
          <Checkbox
            id="use_store_credit"
            :model-value="form.checkout.use_store_credit"
            class="mt-0.5"
            @update:model-value="updateUseStoreCredit"
          />
          <Label for="use_store_credit" class="cursor-pointer leading-5">
            {{ t('commerce.checkout.useStoreCredit') }}
          </Label>
        </div>

        <Button
          type="submit"
          form="checkout-form"
          class="mt-5 w-full"
          :disabled="form.processing || belowMinCheckout"
          :aria-busy="form.processing"
        >
          {{ t('commerce.checkout.payNow') }}
        </Button>
        <Button as-child variant="ghost" class="mt-2 w-full">
          <Link :href="routes.storeCart">{{ t('commerce.checkout.backToCart') }}</Link>
        </Button>
      </section>
    </aside>
  </div>

  <div v-else class="rounded-xl border border-dashed border-border px-6 py-12 text-center">
    <p class="text-sm text-muted-foreground">{{ t('commerce.checkout.emptyCart') }}</p>
    <Button as-child class="mt-5">
      <Link :href="routes.storeCart">{{ t('commerce.checkout.viewCart') }}</Link>
    </Button>
  </div>
</template>
