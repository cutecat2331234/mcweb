<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
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
  }>
  clearUrl?: string
}>()

function clearHistory() {
  if (!props.clearUrl) return
  router.delete(props.clearUrl)
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '商城', href: routes.store },
    { label: '最近浏览', current: true },
  ]" />

  <PageHeader title="最近浏览" subtitle="你最近查看过的商品" />

  <Button v-if="clearUrl && products.length" type="button" variant="outline" size="sm" class="mb-4" @click="clearHistory">清空浏览记录</Button>

  <div v-if="products.length" class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
    <Link
      v-for="product in products"
      :key="product.id"
      :href="product.url"
      class="flex gap-3 rounded-lg border p-3 transition-colors hover:bg-muted/50"
    >
      <img v-if="product.image_url" :src="product.image_url" :alt="product.name" class="h-16 w-16 rounded object-cover" />
      <div>
        <p class="font-medium">{{ product.name }}</p>
        <p class="text-sm text-muted-foreground">{{ product.price_label }}</p>
        <p v-if="product.average_rating" class="text-xs text-amber-600">★ {{ product.average_rating }}</p>
      </div>
    </Link>
  </div>
  <p v-else class="text-sm text-muted-foreground">暂无浏览记录。</p>

  <Button as-child variant="outline" class="mt-6">
    <Link :href="routes.store">返回商城</Link>
  </Button>
</template>
