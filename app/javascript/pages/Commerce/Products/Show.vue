<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Card from '@/components/ui/Card.vue'
import CardContent from '@/components/ui/CardContent.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

export interface ProductDetail {
  id: string
  db_id: number
  name: string
  slug: string
  description: string | null
  price_label: string
  product_type: string
  category_name: string | null
  in_stock: boolean
}

const props = defineProps<{
  product: ProductDetail
  addToCartUrl: string
}>()

function addToCart() {
  router.patch(props.addToCartUrl, {
    product_id: props.product.db_id,
    quantity: 1,
  })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '商城', href: routes.store },
    { label: product.name, current: true },
  ]" />

  <PageHeader :title="product.name" :subtitle="product.description || undefined" />

  <Card class="max-w-xl">
    <CardContent class="space-y-3 pt-6">
      <div class="flex justify-between text-sm">
        <span class="text-muted-foreground">价格</span>
        <span class="font-medium">{{ product.price_label }}</span>
      </div>
      <div class="flex justify-between text-sm">
        <span class="text-muted-foreground">类型</span>
        <span>{{ product.product_type }}</span>
      </div>
      <div class="flex justify-between text-sm">
        <span class="text-muted-foreground">分类</span>
        <span>{{ product.category_name || '—' }}</span>
      </div>
      <div class="flex justify-between text-sm">
        <span class="text-muted-foreground">库存</span>
        <span>{{ product.in_stock ? '有货' : '缺货' }}</span>
      </div>
    </CardContent>
  </Card>

  <div class="mt-6 flex gap-3">
    <Button v-if="product.in_stock" type="button" @click="addToCart">加入购物车</Button>
    <Button as-child variant="outline">
      <Link :href="routes.store">返回商城</Link>
    </Button>
  </div>
</template>
