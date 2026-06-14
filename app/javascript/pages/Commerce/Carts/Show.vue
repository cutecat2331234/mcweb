<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { Link, router } from '@inertiajs/vue3'
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
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

export interface CartItem {
  id: number
  product_name: string
  variant_name: string | null
  quantity: number
  minimum_quantity?: number
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
      couponError.value = data.error || '优惠券无效'
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
      giftCardError.value = data.error || '礼品卡无效'
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

function clearCart() {
  if (!props.clearCartUrl || !confirm('确定清空购物车？')) return
  router.delete(props.clearCartUrl)
}
</script>

<template>
  <PageHeader title="购物车" />

  <div v-if="items.length" class="space-y-6">
    <div class="rounded-lg border">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>商品</TableHead>
            <TableHead>数量</TableHead>
            <TableHead>单价</TableHead>
            <TableHead>小计</TableHead>
            <TableHead />
          </TableRow>
        </TableHeader>
        <TableBody>
          <TableRow v-for="item in items" :key="item.id">
            <TableCell>
              <Link v-if="item.product_url" :href="item.product_url" class="hover:underline">{{ item.product_name }}</Link>
              <template v-else>{{ item.product_name }}</template>
              <span v-if="item.variant_name" class="text-muted-foreground"> — {{ item.variant_name }}</span>
              <p v-if="item.minimum_quantity && item.minimum_quantity > 1" class="text-xs text-muted-foreground">最少购买 {{ item.minimum_quantity }} 件</p>
              <p v-if="item.purchase_limit_remaining != null" class="text-xs text-muted-foreground">还可购买 {{ item.purchase_limit_remaining }} 件</p>
            </TableCell>
            <TableCell>
              <input
                type="number"
                :value="item.quantity"
                min="1"
                class="w-16 rounded-md border px-2 py-1 text-sm"
                @change="updateQuantity(item.id, Number(($event.target as HTMLInputElement).value))"
              >
            </TableCell>
            <TableCell>{{ item.unit_price_label }}</TableCell>
            <TableCell>{{ item.total_label }}</TableCell>
            <TableCell>
              <div class="flex gap-1">
                <Button variant="ghost" size="sm" type="button" @click="removeItem(item.id)">移除</Button>
                <Button
                  v-if="loggedIn && moveToWishlistUrl"
                  variant="ghost"
                  size="sm"
                  type="button"
                  @click="moveToWishlist(item.id)"
                >
                  移入心愿单
                </Button>
              </div>
            </TableCell>
          </TableRow>
        </TableBody>
      </Table>
    </div>

    <p class="font-medium">小计：{{ subtotalLabel }}</p>
    <p v-if="shippingLabel" class="text-sm text-muted-foreground">
      运费：{{ freeShipping ? '免运费' : shippingLabel }}
    </p>
    <p
      v-if="freeShippingRemainingLabel && !freeShipping"
      class="text-xs text-muted-foreground"
    >
      再购 {{ freeShippingRemainingLabel }} 即可免运费（满 {{ freeShippingMinLabel }} 免运费）
    </p>

    <div class="max-w-md space-y-2 rounded-lg border p-4">
      <Label for="coupon">优惠券</Label>
      <div class="flex gap-2">
        <Input id="coupon" v-model="couponCode" placeholder="输入优惠码" class="flex-1" />
        <Button type="button" variant="outline" :disabled="couponLoading || !couponCode.trim()" @click="previewCoupon">
          {{ couponLoading ? '验证中…' : '预览' }}
        </Button>
        <Button v-if="clearCouponUrl && pendingCouponCode" type="button" variant="ghost" @click="clearCoupon">清除</Button>
      </div>
      <p v-if="couponError" class="text-sm text-destructive">{{ couponError }}</p>
      <p v-if="couponPreview" class="text-sm text-muted-foreground">
        优惠码 <strong>{{ couponPreview.code }}</strong> 已应用，减免 {{ couponPreview.discount_label }}，预计合计 {{ couponPreview.total_label }}
        <span v-if="couponPreview.min_amount_label" class="block text-xs">最低消费 {{ couponPreview.min_amount_label }}</span>
      </p>
      <p v-if="couponError && couponPreview?.amount_remaining_label" class="text-xs text-amber-600">
        还差 {{ couponPreview.amount_remaining_label }} 可用此优惠码
      </p>
      <p v-else-if="pendingCouponCode" class="text-sm text-muted-foreground">已保存优惠码：<strong>{{ pendingCouponCode }}</strong>（结账时自动使用）</p>
      <p class="text-xs text-muted-foreground">优惠码在结账时正式使用。</p>
    </div>

    <div class="max-w-md space-y-2 rounded-lg border p-4">
      <Label for="gift_card">礼品卡</Label>
      <div class="flex gap-2">
        <Input id="gift_card" v-model="giftCardCode" placeholder="输入礼品卡代码" class="flex-1" />
        <Button type="button" variant="outline" :disabled="giftCardLoading || !giftCardCode.trim()" @click="previewGiftCard">
          {{ giftCardLoading ? '验证中…' : '预览' }}
        </Button>
        <Button v-if="clearGiftCardUrl && pendingGiftCardCode" type="button" variant="ghost" @click="clearGiftCard">清除</Button>
      </div>
      <p v-if="giftCardError" class="text-sm text-destructive">{{ giftCardError }}</p>
      <p v-if="giftCardPreview" class="text-sm text-muted-foreground">
        礼品卡 <strong>{{ giftCardPreview.code }}</strong> 可抵扣 {{ giftCardPreview.gift_card_amount_label }}，预计合计 {{ giftCardPreview.total_label }}
      </p>
      <p v-else-if="pendingGiftCardCode" class="text-sm text-muted-foreground">已保存礼品卡：<strong>{{ pendingGiftCardCode }}</strong>（结账时自动使用）</p>
    </div>

    <div v-if="loggedIn" class="flex flex-wrap gap-3">
      <Button as-child>
        <Link :href="routes.storeCheckout">去结算</Link>
      </Button>
      <Button v-if="clearCartUrl" type="button" variant="outline" @click="clearCart">清空购物车</Button>
    </div>
    <div v-else class="space-y-3">
      <p class="text-sm text-muted-foreground">请先登录后再结账。</p>
      <Button as-child variant="outline">
        <Link :href="routes.signIn">登录</Link>
      </Button>
    </div>

    <section v-if="crossSellProducts?.length" class="mt-8">
      <h2 class="mb-3 text-sm font-semibold">猜你喜欢</h2>
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
    <p class="text-sm text-muted-foreground">购物车是空的。</p>
    <Button as-child variant="outline">
      <Link :href="routes.store">浏览商品</Link>
    </Button>
  </div>
</template>
