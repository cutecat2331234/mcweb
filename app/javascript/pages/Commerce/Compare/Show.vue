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
    db_id: number
    name: string
    url: string
    price_label: string
    category_name: string | null
    in_stock: boolean
    average_rating: number | null
    view_count: number
    variants: Array<{ id: number; name: string; price_label: string; in_stock: boolean }>
    toggle_url: string
    add_to_cart_url: string
  }>
  compareCount: number
}>()

function remove(product: { toggle_url: string }) {
  router.post(product.toggle_url, {}, { preserveScroll: true })
}

function clearAll() {
  router.delete(routes.storeCompare)
}

function addToCart(product: { db_id: number; add_to_cart_url: string; variants: Array<{ id: number; in_stock: boolean }> }) {
  const variant = product.variants.find((v) => v.in_stock) || product.variants[0]
  router.patch(product.add_to_cart_url, {
    product_id: product.db_id,
    variant_id: variant?.id,
    quantity: 1,
  })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '商城', href: routes.store },
    { label: '商品对比', current: true },
  ]" />

  <div class="mb-4 flex items-center justify-between gap-3">
    <PageHeader title="商品对比" :subtitle="`已选 ${compareCount} 件（最多 4 件）`" />
    <Button v-if="products.length" type="button" variant="outline" size="sm" @click="clearAll">清空对比</Button>
  </div>

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
        <tr class="border-b">
          <td class="p-3 text-muted-foreground">浏览量</td>
          <td v-for="product in products" :key="`${product.id}-views`" class="p-3">{{ product.view_count }}</td>
        </tr>
        <tr class="border-b">
          <td class="p-3 text-muted-foreground">规格</td>
          <td v-for="product in products" :key="`${product.id}-variants`" class="p-3 text-xs">
            <div v-if="product.variants.length">
              <div v-for="variant in product.variants" :key="variant.id">{{ variant.name }} · {{ variant.price_label }} · {{ variant.in_stock ? '有货' : '缺货' }}</div>
            </div>
            <span v-else>—</span>
          </td>
        </tr>
        <tr>
          <td class="p-3 text-muted-foreground">操作</td>
          <td v-for="product in products" :key="`${product.id}-action`" class="space-y-2 p-3">
            <Button
              v-if="product.in_stock"
              type="button"
              size="sm"
              @click="addToCart(product)"
            >
              加入购物车
            </Button>
            <Button type="button" variant="outline" size="sm" @click="remove(product)">移除</Button>
          </td>
        </tr>
      </tbody>
    </table>
  </div>
  <p v-else class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
    对比列表为空。在商品页点击「加入对比」添加商品。
  </p>
</template>
