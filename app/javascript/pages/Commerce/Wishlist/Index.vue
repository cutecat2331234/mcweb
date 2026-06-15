<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Badge from '@/components/ui/Badge.vue'
import Button from '@/components/ui/Button.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const props = defineProps<{
  products: Array<{
    id: string
    name: string
    slug: string
    price_label: string
    compare_at_label?: string | null
    on_sale?: boolean
    discount_label?: string | null
    url: string
    in_stock?: boolean
    low_stock?: boolean
    wishlist_url?: string
    add_to_cart_url?: string
    saved_variant_name?: string
    price_alert_url?: string
    has_price_alert?: boolean
    note?: string
    update_note_url?: string
    coming_soon?: boolean
    available_at_label?: string | null
    availability_alert_url?: string
    has_availability_alert?: boolean
    availability_alert_unsubscribe_url?: string
  }>
  shareUrl: string | null
  addAllToCartUrl?: string
}>()

function addAllToCart() {
  if (!props.addAllToCartUrl) return
  router.post(props.addAllToCartUrl)
}

function addToCart(url: string) {
  router.post(url)
}

function removeFromWishlist(url: string) {
  router.post(url, {}, { preserveScroll: true })
}

function togglePriceAlert(url: string) {
  router.post(url, {}, { preserveScroll: true })
}

function subscribeAvailabilityAlert(url: string) {
  router.post(url, {}, { preserveScroll: true })
}

function unsubscribeAvailabilityAlert(url: string) {
  router.delete(url, { preserveScroll: true })
}

function saveNote(product: { update_note_url?: string; note?: string }) {
  if (!product.update_note_url) return
  router.patch(product.update_note_url, { note: product.note || '' }, { preserveScroll: true })
}

function copyShareLink() {
  if (!props.shareUrl) return
  navigator.clipboard.writeText(props.shareUrl)
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '商城', href: routes.store },
    { label: '心愿单', current: true },
  ]" />

  <div class="mb-4 flex items-center justify-between gap-3">
    <PageHeader title="我的心愿单" />
    <div class="flex gap-2">
      <Button v-if="addAllToCartUrl && products.length" type="button" size="sm" @click="addAllToCart">全部加入购物车</Button>
      <Button v-if="shareUrl" type="button" variant="outline" size="sm" @click="copyShareLink">复制分享链接</Button>
      <Button type="button" variant="outline" size="sm" @click="router.post(routes.storeWishlistShare)">生成分享链接</Button>
    </div>
  </div>
  <p v-if="shareUrl" class="mb-4 text-xs text-muted-foreground break-all">{{ shareUrl }}</p>

  <div v-if="products.length" class="divide-y rounded-lg border">
    <div v-for="product in products" :key="product.id" class="flex items-center justify-between gap-4 p-4">
      <div>
        <Link :href="product.url" class="font-medium hover:underline">{{ product.name }}</Link>
        <Badge v-if="product.coming_soon" variant="outline" class="ml-2 text-[10px]">即将上架</Badge>
        <p class="text-sm">
          <span class="font-medium">{{ product.price_label }}</span>
          <span v-if="product.on_sale && product.compare_at_label" class="ml-2 text-xs text-muted-foreground line-through">{{ product.compare_at_label }}</span>
          <Badge v-if="product.discount_label" variant="outline" class="ml-1 text-[10px]">{{ product.discount_label }}</Badge>
        </p>
        <p v-if="product.saved_variant_name" class="text-xs text-muted-foreground">规格：{{ product.saved_variant_name }}</p>
        <div v-if="product.update_note_url" class="mt-2 flex max-w-md gap-2">
          <input
            v-model="product.note"
            type="text"
            placeholder="添加备注…"
            class="h-8 flex-1 rounded-md border px-2 text-xs"
            @keydown.enter.prevent="saveNote(product)"
          >
          <Button type="button" size="sm" variant="outline" @click="saveNote(product)">保存备注</Button>
        </div>
        <p v-if="product.coming_soon && product.available_at_label" class="text-xs text-muted-foreground">上架时间：{{ product.available_at_label }}</p>
        <div v-if="product.coming_soon && product.availability_alert_url" class="mt-2">
          <Button
            v-if="!product.has_availability_alert"
            type="button"
            size="sm"
            variant="secondary"
            @click="subscribeAvailabilityAlert(product.availability_alert_url!)"
          >
            上架通知
          </Button>
          <Button
            v-else-if="product.availability_alert_unsubscribe_url"
            type="button"
            size="sm"
            variant="outline"
            @click="unsubscribeAvailabilityAlert(product.availability_alert_unsubscribe_url!)"
          >
            已订阅上架
          </Button>
        </div>
        <Badge v-if="product.coming_soon" variant="outline" class="mt-1">未开售</Badge>
        <Badge v-else-if="!product.in_stock" variant="default" class="mt-1">缺货</Badge>
        <Badge v-else-if="product.low_stock" variant="default" class="mt-1">库存紧张</Badge>
      </div>
      <div class="flex gap-2">
        <Button v-if="product.add_to_cart_url && product.in_stock && !product.coming_soon" type="button" size="sm" @click="addToCart(product.add_to_cart_url)">加入购物车</Button>
        <Button
          v-if="product.price_alert_url"
          type="button"
          size="sm"
          :variant="product.has_price_alert ? 'outline' : 'secondary'"
          @click="togglePriceAlert(product.price_alert_url)"
        >
          {{ product.has_price_alert ? '已订阅降价' : '降价提醒' }}
        </Button>
        <Button v-if="product.wishlist_url" type="button" variant="outline" size="sm" @click="removeFromWishlist(product.wishlist_url)">移除</Button>
        <Button as-child variant="outline" size="sm">
          <Link :href="product.url">查看</Link>
        </Button>
      </div>
    </div>
  </div>
  <p v-else class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
    心愿单是空的。浏览商城添加喜欢的商品吧。
  </p>
</template>
