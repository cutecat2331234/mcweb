<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { Link, router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import { confirm } from '@/lib/useConfirm'
import { routes } from '@/lib/routes'
import { csrfHeaders } from '@/lib/csrf'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

export interface CartItem {
  id: number
  product_name: string
  variant_name: string | null
  quantity: number
  gift_note?: string | null
  minimum_quantity?: number
  maximum_quantity?: number | null
  purchase_limit_remaining?: number | null
  unit_price_label: string
  total_label: string
  product_url?: string
}

const props = defineProps<{
  items: CartItem[]
  subtotalLabel: string
  subtotalCents?: number
  shippingLabel?: string | null
  freeShipping?: boolean
  freeShippingMinLabel?: string | null
  freeShippingRemainingLabel?: string | null
  couponFreeShipping?: boolean
  noShippableItems?: boolean
  couponAutoApplied?: boolean
  loggedIn: boolean
  pendingCouponCode?: string | null
  pendingGiftCardCode?: string | null
  previewCouponUrl: string
  previewGiftCardUrl?: string
  clearCouponUrl?: string
  clearGiftCardUrl?: string
  moveToWishlistUrl?: string
  clearCartUrl?: string
  crossSellProducts?: Array<{
    id: string
    name: string
    price_label: string
    url: string
    image_url?: string | null
    summary?: string | null
  }>
  cartRecovered?: boolean
  blockedItemCount?: number
}>()

const couponCode = ref(props.pendingCouponCode || '')
const couponPreview = ref<{
  code: string
  discount_label: string
  total_label: string
  min_amount_label?: string | null
  amount_remaining_label?: string | null
} | null>(null)
const couponError = ref('')
const couponLoading = ref(false)

const giftCardCode = ref(props.pendingGiftCardCode || '')
const giftCardPreview = ref<{
  code: string
  gift_card_amount_label: string
  total_label: string
} | null>(null)
const giftCardError = ref('')
const giftCardLoading = ref(false)

onMounted(() => {
  if (props.pendingCouponCode) {
    couponCode.value = props.pendingCouponCode
  }
  if (props.pendingGiftCardCode) {
    giftCardCode.value = props.pendingGiftCardCode
  }
})

async function previewCoupon() {
  if (!couponCode.value.trim()) return
  couponLoading.value = true
  couponError.value = ''
  couponPreview.value = null
  try {
    const res = await fetch(props.previewCouponUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
        ...csrfHeaders(),
      },
      body: JSON.stringify({ code: couponCode.value.trim() }),
      credentials: 'same-origin',
    })
    const data = await res.json()
    if (!res.ok) {
      couponError.value = data.error || t('commerce.cart.invalidCoupon')
      return
    }
    couponPreview.value = data
  } finally {
    couponLoading.value = false
  }
}

function clearCoupon() {
  if (!props.clearCouponUrl) return
  router.delete(props.clearCouponUrl)
}

async function previewGiftCard() {
  if (!props.previewGiftCardUrl || !giftCardCode.value.trim()) return
  giftCardLoading.value = true
  giftCardError.value = ''
  giftCardPreview.value = null
  try {
    const res = await fetch(props.previewGiftCardUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
        ...csrfHeaders(),
      },
      body: JSON.stringify({
        code: giftCardCode.value.trim(),
        coupon_code: couponCode.value.trim() || undefined,
      }),
      credentials: 'same-origin',
    })
    const data = await res.json()
    if (!res.ok) {
      giftCardError.value = data.error || t('commerce.cart.invalidGiftCard')
      return
    }
    giftCardPreview.value = data
  } finally {
    giftCardLoading.value = false
  }
}

function clearGiftCard() {
  if (!props.clearGiftCardUrl) return
  router.delete(props.clearGiftCardUrl)
}

function updateQuantity(itemId: number, quantity: number) {
  router.patch(routes.storeCart, { item_id: itemId, quantity })
}

function removeItem(itemId: number) {
  router.patch(routes.storeCart, { item_id: itemId, quantity: 0 })
}

function moveToWishlist(itemId: number) {
  if (!props.moveToWishlistUrl) return
  router.post(props.moveToWishlistUrl, { item_id: itemId })
}

async function clearCart() {
  const ok = await confirm({
    title: t('commerce.cart.clearCart'),
    message: t('commerce.cart.clearCartConfirm'),
    confirmLabel: t('commerce.cart.clear'),
    variant: 'destructive',
  })
  if (!props.clearCartUrl || !ok) return
  router.delete(props.clearCartUrl)
}

function updateGiftNote(itemId: number, giftNote: string) {
  router.patch(routes.storeCart, { item_id: itemId, gift_note: giftNote }, { preserveScroll: true })
}
</script>

<template>
  <PageHeader :title="t('commerce.cart.title')" />

  <p
    v-if="cartRecovered"
    role="status"
    class="
      mb-4 rounded-xl border border-green-500/30 bg-green-500/10 px-4 py-3
      text-sm leading-6 text-green-900 dark:text-green-100
    "
  >
    {{ t('commerce.cart.recovered') }}
  </p>

  <p
    v-if="blockedItemCount && blockedItemCount > 0"
    role="alert"
    class="
      mb-4 rounded-xl border border-amber-500/30 bg-amber-500/10 px-4 py-3
      text-sm leading-6 text-amber-900 dark:text-amber-100
    "
  >
    {{ t('commerce.cart.blockedItemsHint', { count: blockedItemCount }) }}
  </p>

  <div v-if="items.length" class="space-y-10">
    <div class="grid gap-8 lg:grid-cols-[minmax(0,1fr)_22rem] lg:items-start">
      <section class="min-w-0" :aria-label="t('commerce.cart.title')">
        <ul class="divide-y overflow-hidden rounded-xl border border-border bg-card shadow-sm">
          <li v-for="item in items" :key="item.id" class="p-4 sm:p-5">
            <div class="space-y-5">
              <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between sm:gap-4">
                <div class="min-w-0">
                  <Link
                    v-if="item.product_url"
                    :href="item.product_url"
                    class="
                      rounded-sm font-semibold text-foreground underline-offset-4
                      hover:text-primary hover:underline focus-visible:outline-none
                      focus-visible:ring-2 focus-visible:ring-ring
                    "
                  >
                    {{ item.product_name }}
                  </Link>
                  <p v-else class="font-semibold text-foreground">{{ item.product_name }}</p>
                  <p v-if="item.variant_name" class="mt-1 text-sm text-muted-foreground">
                    {{ item.variant_name }}
                  </p>
                  <div
                    v-if="
                      (item.minimum_quantity && item.minimum_quantity > 1)
                        || item.maximum_quantity
                        || item.purchase_limit_remaining != null
                    "
                    :id="`quantity-help-${item.id}`"
                    class="mt-2 flex flex-wrap gap-x-3 gap-y-1 text-xs leading-5 text-muted-foreground"
                  >
                    <span v-if="item.minimum_quantity && item.minimum_quantity > 1">
                      {{ t('commerce.cart.minQty', { n: item.minimum_quantity }) }}
                    </span>
                    <span v-if="item.maximum_quantity">
                      {{ t('commerce.cart.maxQty', { n: item.maximum_quantity }) }}
                    </span>
                    <span v-if="item.purchase_limit_remaining != null">
                      {{ t('commerce.cart.limitRemaining', { n: item.purchase_limit_remaining }) }}
                    </span>
                  </div>
                </div>

                <div class="shrink-0 sm:text-right">
                  <p class="text-xs text-muted-foreground">{{ t('commerce.cart.lineTotal') }}</p>
                  <p class="mt-1 font-semibold tabular-nums">{{ item.total_label }}</p>
                  <p class="mt-1 text-xs text-muted-foreground">
                    {{ t('commerce.cart.unitPrice') }} · {{ item.unit_price_label }}
                  </p>
                </div>
              </div>

              <div class="grid gap-4 sm:grid-cols-[7rem_minmax(0,1fr)] sm:items-end">
                <div class="space-y-2">
                  <Label :for="`quantity-${item.id}`">{{ t('commerce.cart.quantity') }}</Label>
                  <Input
                    :id="`quantity-${item.id}`"
                    type="number"
                    :model-value="item.quantity"
                    min="1"
                    class="w-full"
                    :aria-label="`${t('commerce.cart.quantity')}: ${item.product_name}`"
                    :aria-describedby="
                      (item.minimum_quantity && item.minimum_quantity > 1)
                        || item.maximum_quantity
                        || item.purchase_limit_remaining != null
                        ? `quantity-help-${item.id}`
                        : undefined
                    "
                    @update:model-value="(value) => updateQuantity(item.id, Number(value))"
                  />
                </div>

                <div class="space-y-2">
                  <Label :for="`gift-note-${item.id}`">{{ t('commerce.cart.giftNote') }}</Label>
                  <Input
                    :id="`gift-note-${item.id}`"
                    :model-value="item.gift_note || ''"
                    :placeholder="t('commerce.cart.giftNotePlaceholder')"
                    @change="updateGiftNote(item.id, ($event.target as HTMLInputElement).value)"
                  />
                </div>
              </div>

              <div class="flex flex-wrap justify-end gap-1">
                <Button
                  v-if="loggedIn && moveToWishlistUrl"
                  variant="ghost"
                  size="sm"
                  type="button"
                  :aria-label="`${t('commerce.cart.moveToWishlist')}: ${item.product_name}`"
                  @click="moveToWishlist(item.id)"
                >
                  {{ t('commerce.cart.moveToWishlist') }}
                </Button>
                <Button
                  variant="ghost"
                  size="sm"
                  type="button"
                  class="text-destructive hover:bg-destructive/10 hover:text-destructive"
                  :aria-label="`${t('commerce.cart.remove')}: ${item.product_name}`"
                  @click="removeItem(item.id)"
                >
                  {{ t('commerce.cart.remove') }}
                </Button>
              </div>
            </div>
          </li>
        </ul>
      </section>

      <aside class="space-y-4 lg:sticky lg:top-20">
        <section class="rounded-xl border border-border bg-card p-5 shadow-sm">
          <h2 class="text-base font-semibold">{{ t('commerce.cart.orderSummary') }}</h2>
          <div class="mt-4 space-y-2 text-sm leading-6">
            <p class="font-medium text-foreground">
              {{ t('commerce.cart.subtotal', { amount: subtotalLabel }) }}
            </p>
            <p v-if="shippingLabel" class="text-muted-foreground">
              {{
                t('commerce.cart.shipping', {
                  amount: freeShipping
                    ? (
                      couponFreeShipping
                        ? t('commerce.cart.freeShippingCoupon')
                        : noShippableItems
                          ? t('commerce.cart.noShippingNeeded')
                          : t('commerce.cart.freeShipping')
                    )
                    : shippingLabel,
                })
              }}
            </p>
            <p
              v-if="couponAutoApplied && pendingCouponCode"
              role="status"
              class="text-green-700 dark:text-green-400"
            >
              {{ t('commerce.cart.couponAutoApplied', { code: pendingCouponCode }) }}
            </p>
            <p v-if="freeShippingRemainingLabel && !freeShipping" class="text-xs text-muted-foreground">
              {{
                t('commerce.cart.freeShippingRemaining', {
                  remaining: freeShippingRemainingLabel,
                  min: freeShippingMinLabel,
                })
              }}
            </p>
          </div>

          <div v-if="loggedIn" class="mt-5 space-y-2">
            <Button as-child class="w-full">
              <Link :href="routes.storeCheckout">{{ t('commerce.cart.checkout') }}</Link>
            </Button>
            <Button
              v-if="clearCartUrl"
              type="button"
              variant="ghost"
              class="w-full text-destructive hover:bg-destructive/10 hover:text-destructive"
              @click="clearCart"
            >
              {{ t('commerce.cart.clearCart') }}
            </Button>
          </div>
          <div v-else class="mt-5 space-y-3">
            <p class="text-sm leading-6 text-muted-foreground">{{ t('commerce.cart.loginToCheckout') }}</p>
            <Button as-child variant="outline" class="w-full">
              <Link :href="routes.signIn">{{ t('common.signIn') }}</Link>
            </Button>
          </div>
        </section>

        <section class="overflow-hidden rounded-xl border border-border bg-card shadow-sm">
          <h2 class="px-5 pt-5 text-base font-semibold">{{ t('commerce.cart.promotionCodes') }}</h2>

          <form class="space-y-3 p-5" @submit.prevent="previewCoupon">
            <Label for="coupon">{{ t('commerce.cart.coupon') }}</Label>
            <div class="grid gap-2 sm:grid-cols-[minmax(0,1fr)_auto] lg:grid-cols-1 xl:grid-cols-[minmax(0,1fr)_auto]">
              <Input
                id="coupon"
                v-model="couponCode"
                autocomplete="off"
                :placeholder="t('commerce.cart.couponPlaceholder')"
                aria-describedby="coupon-status coupon-hint"
                :aria-invalid="!!couponError"
              />
              <Button
                type="submit"
                variant="outline"
                :disabled="couponLoading || !couponCode.trim()"
                :aria-busy="couponLoading"
              >
                {{ couponLoading ? t('commerce.cart.validating') : t('commerce.cart.preview') }}
              </Button>
            </div>
            <div id="coupon-status" aria-live="polite" class="space-y-1">
              <p v-if="couponError" role="alert" class="text-sm text-destructive">{{ couponError }}</p>
              <p v-if="couponPreview" class="text-sm leading-6 text-muted-foreground">
                {{
                  t('commerce.cart.couponApplied', {
                    code: couponPreview.code,
                    discount: couponPreview.discount_label,
                    total: couponPreview.total_label,
                  })
                }}
                <span v-if="couponPreview.min_amount_label" class="block text-xs">
                  {{ t('commerce.cart.minSpend', { amount: couponPreview.min_amount_label }) }}
                </span>
              </p>
              <p
                v-if="couponError && couponPreview?.amount_remaining_label"
                class="text-xs text-amber-600 dark:text-amber-400"
              >
                {{ t('commerce.cart.amountRemaining', { amount: couponPreview.amount_remaining_label }) }}
              </p>
              <p v-else-if="pendingCouponCode" class="text-sm text-muted-foreground">
                {{ t('commerce.cart.couponSaved', { code: pendingCouponCode }) }}
              </p>
            </div>
            <div class="flex items-start justify-between gap-3">
              <p id="coupon-hint" class="text-xs leading-5 text-muted-foreground">
                {{ t('commerce.cart.couponHint') }}
              </p>
              <Button
                v-if="clearCouponUrl && pendingCouponCode"
                type="button"
                variant="ghost"
                size="sm"
                class="shrink-0"
                @click="clearCoupon"
              >
                {{ t('commerce.cart.clear') }}
              </Button>
            </div>
          </form>

          <form class="space-y-3 border-t border-border p-5" @submit.prevent="previewGiftCard">
            <Label for="gift_card">{{ t('commerce.cart.giftCard') }}</Label>
            <div class="grid gap-2 sm:grid-cols-[minmax(0,1fr)_auto] lg:grid-cols-1 xl:grid-cols-[minmax(0,1fr)_auto]">
              <Input
                id="gift_card"
                v-model="giftCardCode"
                autocomplete="off"
                :placeholder="t('commerce.cart.giftCardPlaceholder')"
                aria-describedby="gift-card-status"
                :aria-invalid="!!giftCardError"
              />
              <Button
                type="submit"
                variant="outline"
                :disabled="giftCardLoading || !giftCardCode.trim()"
                :aria-busy="giftCardLoading"
              >
                {{ giftCardLoading ? t('commerce.cart.validating') : t('commerce.cart.preview') }}
              </Button>
            </div>
            <div id="gift-card-status" aria-live="polite" class="space-y-1">
              <p v-if="giftCardError" role="alert" class="text-sm text-destructive">{{ giftCardError }}</p>
              <p v-if="giftCardPreview" class="text-sm leading-6 text-muted-foreground">
                {{
                  t('commerce.cart.giftCardApplied', {
                    code: giftCardPreview.code,
                    amount: giftCardPreview.gift_card_amount_label,
                    total: giftCardPreview.total_label,
                  })
                }}
              </p>
              <p v-else-if="pendingGiftCardCode" class="text-sm text-muted-foreground">
                {{ t('commerce.cart.giftCardSaved', { code: pendingGiftCardCode }) }}
              </p>
            </div>
            <Button
              v-if="clearGiftCardUrl && pendingGiftCardCode"
              type="button"
              variant="ghost"
              size="sm"
              @click="clearGiftCard"
            >
              {{ t('commerce.cart.clear') }}
            </Button>
          </form>
        </section>
      </aside>
    </div>

    <section v-if="crossSellProducts?.length" class="space-y-4">
      <h2 class="text-lg font-semibold">{{ t('commerce.cart.crossSell') }}</h2>
      <div class="grid gap-4 sm:grid-cols-2">
        <Link
          v-for="product in crossSellProducts"
          :key="product.id"
          :href="product.url"
          class="
            flex gap-4 rounded-xl border border-border bg-card p-4 shadow-sm
            transition-colors hover:bg-muted/50 focus-visible:outline-none
            focus-visible:ring-2 focus-visible:ring-ring
          "
        >
          <img
            v-if="product.image_url"
            :src="product.image_url"
            alt=""
            class="h-16 w-16 shrink-0 rounded-lg object-cover"
          />
          <div class="min-w-0">
            <p class="font-medium">{{ product.name }}</p>
            <p v-if="product.summary" class="mt-1 line-clamp-2 text-sm leading-5 text-muted-foreground">
              {{ product.summary }}
            </p>
            <p class="mt-2 text-sm font-semibold">{{ product.price_label }}</p>
          </div>
        </Link>
      </div>
    </section>
  </div>

  <div v-else class="rounded-xl border border-dashed border-border px-6 py-12 text-center">
    <p class="text-sm text-muted-foreground">{{ t('commerce.cart.empty') }}</p>
    <Button as-child class="mt-5">
      <Link :href="routes.store">{{ t('commerce.cart.browseProducts') }}</Link>
    </Button>
  </div>
</template>
