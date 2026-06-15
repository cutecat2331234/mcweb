<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Badge from '@/components/ui/Badge.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const props = defineProps<{
  products: Array<{
    id: string
    name: string
    price_label: string
    url: string
    image_url: string | null
    average_rating?: number | null
    in_stock?: boolean
    compare_url?: string
    compared?: boolean
    wishlist_url?: string
    wishlisted?: boolean
  }>
  compareCount?: number
  loggedIn?: boolean
  clearUrl?: string
}>()

function clearHistory() {
  if (!props.clearUrl) return
  router.delete(props.clearUrl)
}

function toggleCompare(url: string) {
  router.post(url, {}, { preserveScroll: true })
}

function toggleWishlist(url: string) {
  router.post(url, {}, { preserveScroll: true })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '商城', href: routes.store },
    { label: '最近浏览', current: true },
  ]" />

  <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
    <PageHeader title="最近浏览" subtitle="你最近查看过的商品" />
    <Link v-if="compareCount" :href="routes.storeCompare" class="text-sm text-primary hover:underline">
      对比列表 ({{ compareCount }})
    </Link>
  </div>

  <Button v-if="clearUrl && products.length" type="button" variant="outline" size="sm" class="mb-4" @click="clearHistory">清空浏览记录</Button>

  <div v-if="products.length" class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
    <div
      v-for="product in products"
      :key="product.id"
      class="flex gap-3 rounded-lg border p-3"
    >
      <Link :href="product.url" class="shrink-0">
        <img v-if="product.image_url" :src="product.image_url" :alt="product.name" class="h-16 w-16 rounded object-cover" />
      </Link>
      <div class="min-w-0 flex-1">
        <Link :href="product.url" class="font-medium hover:underline">{{ product.name }}</Link>
        <p class="text-sm text-muted-foreground">{{ product.price_label }}</p>
        <p v-if="product.average_rating" class="text-xs text-amber-600">★ {{ product.average_rating }}</p>
        <div v-if="loggedIn" class="mt-2 flex flex-wrap gap-1">
          <Button
            v-if="product.compare_url"
            type="button"
            size="sm"
            variant="outline"
            @click="toggleCompare(product.compare_url!)"
          >
            {{ product.compared ? '对比中' : '对比' }}
          </Button>
          <Button
            v-if="product.wishlist_url"
            type="button"
            size="sm"
            :variant="product.wishlisted ? 'outline' : 'secondary'"
            @click="toggleWishlist(product.wishlist_url!)"
          >
            {{ product.wishlisted ? '心愿单' : '收藏' }}
          </Button>
        </div>
      </div>
    </div>
  </div>
  <p v-else class="text-sm text-muted-foreground">暂无浏览记录。</p>

  <Button as-child variant="outline" class="mt-6">
    <Link :href="routes.store">返回商城</Link>
  </Button>
</template>
