<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

defineProps<{
  owner: string
  products: Array<{
    id: string
    name: string
    url: string
    price_label: string
    category_name: string | null
    in_stock: boolean
    average_rating: number | null
  }>
}>()
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '商城', href: routes.store },
    { label: '分享对比', current: true },
  ]" />

  <PageHeader :title="`${owner} 的对比列表`" subtitle="公开分享的商品对比" />

  <div v-if="products.length" class="overflow-x-auto">
    <table class="w-full min-w-[640px] border text-sm">
      <thead>
        <tr class="border-b bg-muted/50">
          <th class="p-3 text-left">属性</th>
          <th v-for="product in products" :key="product.id" class="p-3 text-left">
            <Link :href="product.url" class="font-medium hover:underline">{{ product.name }}</Link>
          </th>
        </tr>
      </thead>
      <tbody>
        <tr class="border-b">
          <td class="p-3 text-muted-foreground">价格</td>
          <td v-for="product in products" :key="`${product.id}-price`" class="p-3">{{ product.price_label }}</td>
        </tr>
        <tr class="border-b">
          <td class="p-3 text-muted-foreground">分类</td>
          <td v-for="product in products" :key="`${product.id}-cat`" class="p-3">{{ product.category_name || '—' }}</td>
        </tr>
        <tr class="border-b">
          <td class="p-3 text-muted-foreground">库存</td>
          <td v-for="product in products" :key="`${product.id}-stock`" class="p-3">{{ product.in_stock ? '有货' : '缺货' }}</td>
        </tr>
        <tr class="border-b">
          <td class="p-3 text-muted-foreground">评分</td>
          <td v-for="product in products" :key="`${product.id}-rating`" class="p-3">{{ product.average_rating ?? '—' }}</td>
        </tr>
      </tbody>
    </table>
  </div>
  <p v-else class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
    对比列表为空或商品已下架。
  </p>

  <div class="mt-4">
    <Button as-child variant="outline">
      <Link :href="routes.storeCompare">创建自己的对比</Link>
    </Button>
  </div>
</template>
