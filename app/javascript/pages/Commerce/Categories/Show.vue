<script setup lang="ts">
import { Head, Link, router } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import Badge from '@/components/ui/Badge.vue'
import Button from '@/components/ui/Button.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const props = defineProps<{
  category: {
    slug: string
    name: string
    description?: string | null
    icon?: string | null
    color_hex?: string | null
    seo_title?: string
    seo_description?: string | null
  }
  products: Array<{
    public_id: string
    name: string
    url: string
    price_label: string
    compare_at_label?: string | null
    on_sale?: boolean
    in_stock: boolean
    low_stock: boolean
  }>
  pagination: PaginationMeta
  query: string
  filters: { in_stock: boolean; on_sale: boolean; sort: string }
}>()

function applyFilter(key: 'in_stock' | 'on_sale', value: boolean) {
  router.get(routes.storeCategory(props.category.slug), {
    q: props.query || undefined,
    in_stock: key === 'in_stock' ? (value ? '1' : undefined) : (props.filters.in_stock ? '1' : undefined),
    on_sale: key === 'on_sale' ? (value ? '1' : undefined) : (props.filters.on_sale ? '1' : undefined),
    sort: props.filters.sort || undefined,
  }, { preserveState: true })
}
</script>

<template>
  <Head v-if="category.seo_title">
    <title>{{ category.seo_title }}</title>
    <meta v-if="category.seo_description" head-key="description" name="description" :content="category.seo_description" />
    <meta head-key="og:title" property="og:title" :content="category.seo_title" />
    <meta v-if="category.seo_description" head-key="og:description" property="og:description" :content="category.seo_description" />
  </Head>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '商城', href: routes.store },
    { label: category.name, current: true },
  ]" />

  <PageHeader :title="`${category.icon ? category.icon + ' ' : ''}${category.name}`" :subtitle="category.description || '分类商品'" />
  <div v-if="category.color_hex" class="mb-4 h-1 w-full max-w-xl rounded-full" :style="{ backgroundColor: category.color_hex }" />

  <div class="mb-4 flex flex-wrap gap-2">
    <Button type="button" size="sm" :variant="filters.in_stock ? 'default' : 'outline'" @click="applyFilter('in_stock', !filters.in_stock)">
      仅有货
    </Button>
    <Button type="button" size="sm" :variant="filters.on_sale ? 'default' : 'outline'" @click="applyFilter('on_sale', !filters.on_sale)">
      促销中
    </Button>
  </div>

  <div v-if="products.length" class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
    <Link
      v-for="product in products"
      :key="product.public_id"
      :href="product.url"
      class="rounded-lg border p-4 no-underline transition-colors hover:bg-muted/40"
    >
      <h3 class="font-medium text-foreground">{{ product.name }}</h3>
      <p class="mt-2 text-sm">
        <span class="font-semibold text-primary">{{ product.price_label }}</span>
        <span v-if="product.compare_at_label" class="ml-2 text-muted-foreground line-through">{{ product.compare_at_label }}</span>
      </p>
      <div class="mt-2 flex gap-2">
        <Badge v-if="!product.in_stock" variant="secondary">缺货</Badge>
        <Badge v-else-if="product.low_stock" variant="outline">库存紧张</Badge>
        <Badge v-if="product.on_sale" variant="default">促销</Badge>
      </div>
    </Link>
  </div>
  <p v-else class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">该分类暂无商品。</p>

  <Pagination v-if="pagination" class="mt-6" :meta="pagination" />
</template>
