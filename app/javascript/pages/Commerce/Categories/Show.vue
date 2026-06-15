<script setup lang="ts">
import { Head, Link, router } from '@inertiajs/vue3'
import { ref } from 'vue'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import Badge from '@/components/ui/Badge.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
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
    rss_url?: string
  }
  products: Array<{
    id: string
    name: string
    url: string
    price_label: string
    compare_at_label?: string | null
    on_sale?: boolean
    in_stock: boolean
    low_stock: boolean
    compare_url?: string
    compared?: boolean
    wishlist_url?: string
    wishlisted?: boolean
  }>
  pagination: PaginationMeta
  query: string
  priceMin?: string
  priceMax?: string
  compareCount?: number
  loggedIn?: boolean
  filters: { in_stock: boolean; on_sale: boolean; sort: string }
}>()

const q = ref(props.query)
const priceMin = ref(props.priceMin ?? '')
const priceMax = ref(props.priceMax ?? '')

const hasActiveFilters = !!(
  props.query || props.filters.in_stock || props.filters.on_sale ||
  props.priceMin || props.priceMax || (props.filters.sort && props.filters.sort !== '')
)

const sortLabels: Record<string, string> = {
  price_asc: '价格升序',
  price_desc: '价格降序',
  popular: '最热',
  rating: '评分最高',
  discount_desc: '折扣最大',
}

function filterParams(overrides: Record<string, string | undefined> = {}) {
  return {
    q: overrides.q ?? (q.value || undefined),
    in_stock: props.filters.in_stock ? '1' : undefined,
    on_sale: props.filters.on_sale ? '1' : undefined,
    sort: props.filters.sort || undefined,
    price_min: overrides.price_min ?? (priceMin.value || undefined),
    price_max: overrides.price_max ?? (priceMax.value || undefined),
  }
}

function search() {
  router.get(routes.storeCategory(props.category.slug), filterParams(), { preserveState: true })
}

function clearFilters() {
  router.get(routes.storeCategory(props.category.slug), {}, { preserveState: true })
}

function applyFilter(key: 'in_stock' | 'on_sale', value: boolean) {
  router.get(routes.storeCategory(props.category.slug), {
    ...filterParams(),
    in_stock: key === 'in_stock' ? (value ? '1' : undefined) : (props.filters.in_stock ? '1' : undefined),
    on_sale: key === 'on_sale' ? (value ? '1' : undefined) : (props.filters.on_sale ? '1' : undefined),
  }, { preserveState: true })
}

function applySort(sort: string) {
  router.get(routes.storeCategory(props.category.slug), {
    ...filterParams(),
    sort: sort || undefined,
  }, { preserveState: true })
}

function toggleCompare(url: string) {
  router.post(url, {}, { preserveScroll: true })
}

function toggleWishlist(url: string) {
  router.post(url, {}, { preserveScroll: true })
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

  <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
    <PageHeader :title="`${category.icon ? category.icon + ' ' : ''}${category.name}`" :subtitle="category.description || '分类商品'" />
    <Link v-if="compareCount" :href="routes.storeCompare" class="text-sm text-primary hover:underline">
      对比列表 ({{ compareCount }})
    </Link>
  </div>
  <div v-if="category.color_hex" class="mb-4 h-1 w-full max-w-xl rounded-full" :style="{ backgroundColor: category.color_hex }" />

  <form class="mb-4 flex flex-wrap items-center gap-2" @submit.prevent="search">
    <Input v-model="q" placeholder="搜索本分类商品…" class="max-w-xs" />
    <select
      :value="filters.sort || ''"
      class="h-9 rounded-md border border-input bg-transparent px-3 text-sm"
      @change="applySort(($event.target as HTMLSelectElement).value)"
    >
      <option value="">最新上架</option>
      <option value="popular">最热</option>
      <option value="rating">评分最高</option>
      <option value="price_asc">价格从低到高</option>
      <option value="price_desc">价格从高到低</option>
      <option value="discount_desc">折扣最大</option>
    </select>
    <label class="flex items-center gap-2 text-sm">
      <input
        type="checkbox"
        class="rounded border"
        :checked="filters.in_stock"
        @change="applyFilter('in_stock', !filters.in_stock)"
      />
      仅看有货
    </label>
    <label class="flex items-center gap-2 text-sm">
      <input
        type="checkbox"
        class="rounded border"
        :checked="filters.on_sale"
        @change="applyFilter('on_sale', !filters.on_sale)"
      />
      仅促销
    </label>
    <Input v-model="priceMin" type="number" min="0" step="0.01" placeholder="最低价" class="w-24" />
    <Input v-model="priceMax" type="number" min="0" step="0.01" placeholder="最高价" class="w-24" />
    <button type="submit" class="rounded-md bg-primary px-4 py-2 text-sm text-primary-foreground">筛选</button>
    <Button v-if="hasActiveFilters" type="button" variant="outline" size="sm" @click="clearFilters">清除筛选</Button>
    <a v-if="category.rss_url" :href="category.rss_url" target="_blank" rel="noopener" class="text-sm text-muted-foreground hover:text-foreground">RSS</a>
  </form>

  <div v-if="hasActiveFilters" class="mb-4 flex flex-wrap items-center gap-2 text-xs">
    <span class="text-muted-foreground">当前筛选：</span>
    <Badge v-if="query" variant="outline">关键词：{{ query }}</Badge>
    <Badge v-if="filters.in_stock" variant="outline">仅有货</Badge>
    <Badge v-if="filters.on_sale" variant="outline">促销中</Badge>
    <Badge v-if="priceMin || priceMax" variant="outline">价格区间</Badge>
    <Badge v-if="filters.sort" variant="outline">排序：{{ sortLabels[filters.sort] || filters.sort }}</Badge>
  </div>

  <div v-if="products.length" class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
    <div
      v-for="product in products"
      :key="product.id"
      class="rounded-lg border p-4"
    >
      <Link :href="product.url" class="font-medium text-foreground hover:underline">{{ product.name }}</Link>
      <p class="mt-2 text-sm">
        <span class="font-semibold text-primary">{{ product.price_label }}</span>
        <span v-if="product.compare_at_label" class="ml-2 text-muted-foreground line-through">{{ product.compare_at_label }}</span>
      </p>
      <div class="mt-2 flex flex-wrap gap-2">
        <Badge v-if="!product.in_stock" variant="secondary">缺货</Badge>
        <Badge v-else-if="product.low_stock" variant="outline">库存紧张</Badge>
        <Badge v-if="product.on_sale" variant="default">促销</Badge>
      </div>
      <div v-if="loggedIn" class="mt-3 flex flex-wrap gap-1">
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
  <p v-else class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">该分类暂无商品。</p>

  <Pagination
    v-if="pagination?.pages > 1"
    class="mt-6"
    :pagination="pagination"
    :base-path="routes.storeCategory(category.slug)"
  />
</template>
