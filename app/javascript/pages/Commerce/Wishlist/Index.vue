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
    url: string
    in_stock?: boolean
    low_stock?: boolean
    wishlist_url?: string
  }>
  shareUrl: string | null
  addAllToCartUrl?: string
}>()

function addAllToCart() {
  if (!props.addAllToCartUrl) return
  router.post(props.addAllToCartUrl)
}

function removeFromWishlist(url: string) {
  router.post(url, {}, { preserveScroll: true })
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
        <p class="text-sm text-muted-foreground">{{ product.price_label }}</p>
        <p v-if="product.saved_variant_name" class="text-xs text-muted-foreground">规格：{{ product.saved_variant_name }}</p>
        <Badge v-if="!product.in_stock" variant="default" class="mt-1">缺货</Badge>
        <Badge v-else-if="product.low_stock" variant="default" class="mt-1">库存紧张</Badge>
      </div>
      <div class="flex gap-2">
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
