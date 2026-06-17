<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Badge from '@/components/ui/Badge.vue'
import Button from '@/components/ui/Button.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const props = defineProps<{
  owner: string
  products: Array<{
    id: string
    name: string
    price_label: string
    compare_at_label?: string | null
    on_sale?: boolean
    discount_label?: string | null
    url: string
    saved_variant_name?: string | null
    note?: string
    coming_soon?: boolean
    available_at_label?: string | null
    coming_soon_label?: string | null
  }>
  filters?: { in_stock: boolean; on_sale: boolean; coming_soon: boolean; sort: string }
  totalCount?: number
  filteredCount?: number
}>()

const hasActiveFilters = () =>
  !!(props.filters?.in_stock || props.filters?.on_sale || props.filters?.coming_soon ||
    (props.filters?.sort && props.filters.sort !== 'newest'))
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '商城', href: routes.store },
    { label: '分享心愿单', current: true },
  ]" />

  <PageHeader :title="`${owner} 的心愿单`" subtitle="公开分享列表" />

  <div v-if="hasActiveFilters()" class="mb-4 flex flex-wrap items-center gap-2 text-xs">
    <span class="text-muted-foreground">当前筛选：</span>
    <Badge v-if="filters?.in_stock" variant="outline">有货</Badge>
    <Badge v-if="filters?.on_sale" variant="outline">促销</Badge>
    <Badge v-if="filters?.coming_soon" variant="outline">即将上架</Badge>
    <Badge v-if="filters?.sort && filters.sort !== 'newest'" variant="outline">{{ filters.sort }}</Badge>
    <span v-if="totalCount !== undefined && filteredCount !== undefined" class="text-muted-foreground">
      显示 {{ filteredCount }} / {{ totalCount }} 件
    </span>
  </div>

  <div v-if="products.length" class="divide-y rounded-lg border">
    <div v-for="product in products" :key="product.id" class="flex items-center justify-between p-4">
      <div>
        <Link :href="product.url" class="font-medium hover:underline">{{ product.name }}</Link>
        <Badge v-if="product.coming_soon" variant="outline" class="ml-2 text-[10px]">即将上架</Badge>
        <p class="text-sm">
          <span>{{ product.price_label }}</span>
          <span v-if="product.on_sale && product.compare_at_label" class="ml-2 text-xs text-muted-foreground line-through">{{ product.compare_at_label }}</span>
        </p>
        <p v-if="product.saved_variant_name" class="text-xs text-muted-foreground">规格：{{ product.saved_variant_name }}</p>
        <p v-if="product.note" class="text-xs text-muted-foreground">备注：{{ product.note }}</p>
        <p v-if="product.coming_soon && product.available_at_label" class="text-xs text-muted-foreground">上架时间：{{ product.available_at_label }}</p>
        <p v-if="product.coming_soon_label" class="text-xs text-amber-700">{{ product.coming_soon_label }}</p>
      </div>
      <Button as-child variant="outline" size="sm">
        <Link :href="product.url">{{ product.coming_soon ? '预览' : '查看' }}</Link>
      </Button>
    </div>
  </div>
  <p v-else class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
    {{ hasActiveFilters() ? '当前筛选下没有商品。' : '心愿单是空的。' }}
  </p>
</template>
