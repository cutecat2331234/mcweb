<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { Link, router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Table from '@/components/ui/Table.vue'
import TableBody from '@/components/ui/TableBody.vue'
import TableCell from '@/components/ui/TableCell.vue'
import TableHead from '@/components/ui/TableHead.vue'
import TableHeader from '@/components/ui/TableHeader.vue'
import TableRow from '@/components/ui/TableRow.vue'
import { confirm } from '@/lib/useConfirm'
import { routes } from '@/lib/routes'

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
    const token = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content
    const res = await fetch(props.previewCouponUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
        'X-CSRF-Token': token || '',
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
    const token = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content
    const res = await fetch(props.previewGiftCardUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
        'X-CSRF-Token': token || '',
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

  <p v-if="cartRecovered" class="mb-4 rounded-lg border border-green-200 bg-green-50 px-4 py-3 text-sm text-green-900">
    {{ t('commerce.cart.recovered') }}
  </p>

  <p
    v-if="blockedItemCount && blockedItemCount > 0"
    class="mb-4 rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900"
  >
    {{ t('commerce.cart.blockedItemsHint', { count: blockedItemCount }) }}
  </p>

  <div v-if="items.length" class="space-y-6">
    <div class="rounded-lg border">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>{{ t('commerce.cart.product') }}</TableHead>
            <TableHead>{{ t('commerce.cart.quantity') }}</TableHead>
            <TableHead>{{ t('commerce.cart.unitPrice') }}</TableHead>
            <TableHead>{{ t('commerce.cart.lineTotal') }}</TableHead>
            <TableHead />
          </TableRow>
        </TableHeader>
        <TableBody>
          <TableRow v-for="item in items" :key="item.id">
            <TableCell>
              <Link v-if="item.product_url" :href="item.product_url" class="hover:underline">{{ item.product_name }}</Link>
              <template v-else>{{ item.product_name }}</template>
              <span v-if="item.variant_name" class="text-muted-foreground"> — {{ item.variant_name }}</span>
              <p v-if="item.minimum_quantity && item.minimum_quantity > 1" class="text-xs text-muted-foreground">{{ t('commerce.cart.minQty', { n: item.minimum_quantity }) }}</p>
              <p v-if="item.maximum_quantity" class="text-xs text-muted-foreground">{{ t('commerce.cart.maxQty', { n: item.maximum_quantity }) }}</p>
              <p v-if="item.purchase_limit_remaining != null" class="text-xs text-muted-foreground">{{ t('commerce.cart.limitRemaining', { n: item.purchase_limit_remaining }) }}</p>
              <div class="mt-2 max-w-xs space-y-1">
                <Label :for="`gift-note-${item.id}`" class="text-xs">{{ t('commerce.cart.giftNote') }}</Label>
                <Input
                  :id="`gift-note-${item.id}`"
                  :model-value="item.gift_note || ''"
                  :placeholder="t('commerce.cart.giftNotePlaceholder')"
                  class="h-8 text-xs"
                  @change="updateGiftNote(item.id, ($event.target as HTMLInputElement).value)"
                />
              </div>
            </TableCell>
            <TableCell>
              <Input
                type="number"
                :model-value="item.quantity"
                min="1"
                class="w-20"
                @update:model-value="(value) => updateQuantity(item.id, Number(value))"
              />
            </TableCell>
            <TableCell>{{ item.unit_price_label }}</TableCell>
            <TableCell>{{ item.total_label }}</TableCell>
            <TableCell>
              <div class="flex gap-1">
                <Button variant="ghost" size="sm" type="button" @click="removeItem(item.id)">{{ t('commerce.cart.remove') }}</Button>
                <Button
                  v-if="loggedIn && moveToWishlistUrl"
                  variant="ghost"
                  size="sm"
                  type="button"
                  @click="moveToWishlist(item.id)"
                >
                  {{ t('commerce.cart.moveToWishlist') }}
                </Button>
              </div>
            </TableCell>
          </TableRow>
        </TableBody>
      </Table>
    </div>

    <p class="font-medium">{{ t('commerce.cart.subtotal', { amount: subtotalLabel }) }}</p>
    <p v-if="shippingLabel" class="text-sm text-muted-foreground">
      {{ t('commerce.cart.shipping', {
        amount: freeShipping
          ? (couponFreeShipping ? t('commerce.cart.freeShippingCoupon') : noShippableItems ? t('commerce.cart.noShippingNeeded') : t('commerce.cart.freeShipping'))
          : shippingLabel
      }) }}
    </p>
    <p v-if="couponAutoApplied && pendingCouponCode" class="text-sm text-green-700">
      {{ t('commerce.cart.couponAutoApplied', { code: pendingCouponCode }) }}
    </p>
    <p
      v-if="freeShippingRemainingLabel && !freeShipping"
      class="text-xs text-muted-foreground"
    >
      {{ t('commerce.cart.freeShippingRemaining', { remaining: freeShippingRemainingLabel, min: freeShippingMinLabel }) }}
    </p>

    <div class="max-w-md space-y-2 rounded-lg border p-4">
      <Label for="coupon">{{ t('commerce.cart.coupon') }}</Label>
      <div class="flex gap-2">
        <Input id="coupon" v-model="couponCode" :placeholder="t('commerce.cart.couponPlaceholder')" class="flex-1" />
        <Button type="button" variant="outline" :disabled="couponLoading || !couponCode.trim()" @click="previewCoupon">
          {{ couponLoading ? t('commerce.cart.validating') : t('commerce.cart.preview') }}
        </Button>
        <Button v-if="clearCouponUrl && pendingCouponCode" type="button" variant="ghost" @click="clearCoupon">{{ t('commerce.cart.clear') }}</Button>
      </div>
      <p v-if="couponError" class="text-sm text-destructive">{{ couponError }}</p>
      <p v-if="couponPreview" class="text-sm text-muted-foreground">
        {{ t('commerce.cart.couponApplied', { code: couponPreview.code, discount: couponPreview.discount_label, total: couponPreview.total_label }) }}
        <span v-if="couponPreview.min_amount_label" class="block text-xs">{{ t('commerce.cart.minSpend', { amount: couponPreview.min_amount_label }) }}</span>
      </p>
      <p v-if="couponError && couponPreview?.amount_remaining_label" class="text-xs text-amber-600">
        {{ t('commerce.cart.amountRemaining', { amount: couponPreview.amount_remaining_label }) }}
      </p>
      <p v-else-if="pendingCouponCode" class="text-sm text-muted-foreground">{{ t('commerce.cart.couponSaved', { code: pendingCouponCode }) }}</p>
      <p class="text-xs text-muted-foreground">{{ t('commerce.cart.couponHint') }}</p>
    </div>

    <div class="max-w-md space-y-2 rounded-lg border p-4">
      <Label for="gift_card">{{ t('commerce.cart.giftCard') }}</Label>
      <div class="flex gap-2">
        <Input id="gift_card" v-model="giftCardCode" :placeholder="t('commerce.cart.giftCardPlaceholder')" class="flex-1" />
        <Button type="button" variant="outline" :disabled="giftCardLoading || !giftCardCode.trim()" @click="previewGiftCard">
          {{ giftCardLoading ? t('commerce.cart.validating') : t('commerce.cart.preview') }}
        </Button>
        <Button v-if="clearGiftCardUrl && pendingGiftCardCode" type="button" variant="ghost" @click="clearGiftCard">{{ t('commerce.cart.clear') }}</Button>
      </div>
      <p v-if="giftCardError" class="text-sm text-destructive">{{ giftCardError }}</p>
      <p v-if="giftCardPreview" class="text-sm text-muted-foreground">
        {{ t('commerce.cart.giftCardApplied', { code: giftCardPreview.code, amount: giftCardPreview.gift_card_amount_label, total: giftCardPreview.total_label }) }}
      </p>
      <p v-else-if="pendingGiftCardCode" class="text-sm text-muted-foreground">{{ t('commerce.cart.giftCardSaved', { code: pendingGiftCardCode }) }}</p>
    </div>

    <div v-if="loggedIn" class="flex flex-wrap gap-3">
      <Button as-child>
        <Link :href="routes.storeCheckout">{{ t('commerce.cart.checkout') }}</Link>
      </Button>
      <Button v-if="clearCartUrl" type="button" variant="outline" @click="clearCart">{{ t('commerce.cart.clearCart') }}</Button>
    </div>
    <div v-else class="space-y-3">
      <p class="text-sm text-muted-foreground">{{ t('commerce.cart.loginToCheckout') }}</p>
      <Button as-child variant="outline">
        <Link :href="routes.signIn">{{ t('common.signIn') }}</Link>
      </Button>
    </div>

    <section v-if="crossSellProducts?.length" class="mt-8">
      <h2 class="mb-3 text-sm font-semibold">{{ t('commerce.cart.crossSell') }}</h2>
      <div class="grid gap-3 sm:grid-cols-2">
        <Link
          v-for="product in crossSellProducts"
          :key="product.id"
          :href="product.url"
          class="flex gap-3 rounded-lg border p-3 transition-colors hover:bg-muted/50"
        >
          <img
            v-if="product.image_url"
            :src="product.image_url"
            :alt="product.name"
            class="h-14 w-14 shrink-0 rounded object-cover"
          />
          <div class="min-w-0">
            <p class="font-medium">{{ product.name }}</p>
            <p v-if="product.summary" class="mt-0.5 line-clamp-2 text-xs text-muted-foreground">{{ product.summary }}</p>
            <p class="mt-1 text-sm font-medium">{{ product.price_label }}</p>
          </div>
        </Link>
      </div>
    </section>
  </div>

  <div v-else class="space-y-4">
    <p class="text-sm text-muted-foreground">{{ t('commerce.cart.empty') }}</p>
    <Button as-child variant="outline">
      <Link :href="routes.store">{{ t('commerce.cart.browseProducts') }}</Link>
    </Button>
  </div>
</template>
