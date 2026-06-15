<script setup lang="ts">
import { Head, Link, router } from '@inertiajs/vue3'
import { ref, computed } from 'vue'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import Badge from '@/components/ui/Badge.vue'
import Input from '@/components/ui/Input.vue'
import Button from '@/components/ui/Button.vue'
import Table from '@/components/ui/Table.vue'
import TableBody from '@/components/ui/TableBody.vue'
import TableCell from '@/components/ui/TableCell.vue'
import TableHead from '@/components/ui/TableHead.vue'
import TableHeader from '@/components/ui/TableHeader.vue'
import TableRow from '@/components/ui/TableRow.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

export interface ProductItem {
  db_id?: number
  id: string
  name: string
  slug: string
  category_name: string | null
  price_label: string
  compare_at_label?: string | null
  on_sale?: boolean
  discount_percent?: number | null
  discount_label?: string | null
  in_stock: boolean
  low_stock: boolean
  average_rating?: number | null
  image_url: string | null
  summary?: string | null
  url: string
  quick_addable?: boolean
  preview_url?: string | null
  coming_soon_label?: string | null
  available_at_label?: string | null
  has_availability_alert?: boolean
  availability_alert_url?: string | null
  availability_alert_unsubscribe_url?: string | null
  compare_url?: string
  compared?: boolean
}

export interface CategoryItem {
  slug: string
  name: string
  url: string
  product_count?: number
}

const props = defineProps<{
  products: ProductItem[]
  featured_products?: ProductItem[]
  recently_viewed?: ProductItem[]
  upcoming_products?: ProductItem[]
  categories: CategoryItem[]
  activeCategory: string | null
  query: string
  sort: string
  inStock?: boolean
  onSale?: boolean
  priceMin?: string
  priceMax?: string
  pagination: PaginationMeta
  compareCount?: number
  seo_title?: string
  seo_description?: string | null
  rss_url?: string
  loggedIn?: boolean
}>()

const q = ref(props.query)
const sort = ref(props.sort)
const inStock = ref(props.inStock ?? false)
const onSale = ref(props.onSale ?? false)
const priceMin = ref(props.priceMin ?? '')
const priceMax = ref(props.priceMax ?? '')

function search() {
  router.get(routes.store, {
    q: q.value || undefined,
    sort: sort.value !== 'newest' ? sort.value : undefined,
    category: props.activeCategory || undefined,
    in_stock: inStock.value ? '1' : undefined,
    on_sale: onSale.value ? '1' : undefined,
    price_min: priceMin.value || undefined,
    price_max: priceMax.value || undefined,
  }, { preserveState: true })
}

function subscribeAvailabilityAlert(url: string) {
  router.post(url, {}, { preserveScroll: true })
}

function unsubscribeAvailabilityAlert(url: string) {
  router.delete(url, { preserveScroll: true })
}

function quickAdd(product: ProductItem) {
  if (!product.db_id) return
  router.post(routes.storeCart, { product_id: product.db_id, quantity: 1 }, { preserveScroll: true })
}

function toggleCompare(url: string) {
  router.post(url, {}, { preserveScroll: true })
}

const hasActiveFilters = computed(() =>
  !!(props.query || props.activeCategory || props.inStock || props.onSale ||
    props.priceMin || props.priceMax || (props.sort && props.sort !== 'newest'))
)

function clearFilters() {
  router.get(routes.store, {}, { preserveState: true })
}
</script>

<template>
  <Head v-if="seo_title">
    <title>{{ seo_title }}</title>
    <meta v-if="seo_description" head-key="description" name="description" :content="seo_description" />
    <meta head-key="og:title" property="og:title" :content="seo_title" />
    <meta v-if="seo_description" head-key="og:description" property="og:description" :content="seo_description" />
  </Head>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '商城', current: true },
  ]" />

  <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
    <PageHeader title="商品列表" subtitle="浏览可购买的数字商品" />
    <a v-if="rss_url" :href="rss_url" target="_blank" rel="noopener" class="mb-4 inline-block text-sm text-muted-foreground hover:text-foreground">RSS 订阅最新商品</a>
    <Link v-if="compareCount" :href="routes.storeCompare" class="text-sm text-primary hover:underline">
      对比列表 ({{ compareCount }})
    </Link>
  </div>

  <section v-if="recently_viewed?.length" class="mb-8">
    <div class="mb-3 flex items-center justify-between">
      <h2 class="text-sm font-semibold">最近浏览</h2>
      <Link :href="routes.storeRecentlyViewed" class="text-xs text-primary hover:underline">查看全部</Link>
    </div>
    <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      <Link
        v-for="product in recently_viewed"
        :key="product.id"
        :href="product.url"
        class="flex gap-3 rounded-lg border p-3 transition-colors hover:bg-muted/50"
      >
        <img v-if="product.image_url" :src="product.image_url" :alt="product.name" class="h-16 w-16 rounded object-cover" />
        <div>
          <p class="font-medium">{{ product.name }}</p>
          <p class="text-sm text-muted-foreground">{{ product.price_label }}</p>
        </div>
      </Link>
    </div>
  </section>

  <section v-if="upcoming_products?.length" class="mb-8">
    <h2 class="mb-3 text-sm font-semibold">即将上架</h2>
    <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      <div
        v-for="product in upcoming_products"
        :key="product.id"
        class="flex gap-3 rounded-lg border border-dashed p-3 opacity-90"
      >
        <Link :href="product.preview_url || product.url" class="shrink-0">
          <img v-if="product.image_url" :src="product.image_url" :alt="product.name" class="h-16 w-16 rounded object-cover grayscale hover:opacity-90" />
        </Link>
        <div class="min-w-0 flex-1">
          <Link :href="product.preview_url || product.url" class="font-medium hover:underline">{{ product.name }}</Link>
          <p class="text-sm text-muted-foreground">{{ product.price_label }}</p>
          <Badge v-if="product.available_at_label" class="mt-1">{{ product.available_at_label }}</Badge>
          <div v-if="loggedIn && product.availability_alert_url" class="mt-2">
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
          <div v-if="loggedIn && product.compare_url" class="mt-2">
            <Button
              type="button"
              size="sm"
              variant="outline"
              @click="toggleCompare(product.compare_url!)"
            >
              {{ product.compared ? '移出对比' : '加入对比' }}
            </Button>
          </div>
        </div>
      </div>
    </div>
  </section>

  <section v-if="featured_products?.length" class="mb-8">
    <h2 class="mb-3 text-sm font-semibold">精选商品</h2>
    <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      <Link
        v-for="product in featured_products"
        :key="product.id"
        :href="product.url"
        class="flex gap-3 rounded-lg border p-3 transition-colors hover:bg-muted/50"
      >
        <img v-if="product.image_url" :src="product.image_url" :alt="product.name" class="h-16 w-16 rounded object-cover" />
        <div>
          <p class="font-medium">{{ product.name }}</p>
          <p class="text-sm text-muted-foreground">{{ product.price_label }}</p>
        </div>
      </Link>
    </div>
  </section>

  <form class="mb-4 flex flex-wrap items-center gap-2" @submit.prevent="search">
    <Input v-model="q" placeholder="搜索商品名或 SKU…" class="max-w-xs" />
    <select v-model="sort" class="h-9 rounded-md border border-input bg-transparent px-3 text-sm">
      <option value="newest">最新</option>
      <option value="popular">最热</option>
      <option value="rating">评分最高</option>
      <option value="price_asc">价格升序</option>
      <option value="price_desc">价格降序</option>
      <option value="discount_desc">折扣最大</option>
    </select>
    <label class="flex items-center gap-2 text-sm">
      <input v-model="inStock" type="checkbox" class="rounded border" />
      仅看有货
    </label>
    <label class="flex items-center gap-2 text-sm">
      <input v-model="onSale" type="checkbox" class="rounded border" />
      仅促销
    </label>
    <Input v-model="priceMin" type="number" min="0" step="0.01" placeholder="最低价" class="w-24" />
    <Input v-model="priceMax" type="number" min="0" step="0.01" placeholder="最高价" class="w-24" />
    <button type="submit" class="rounded-md bg-primary px-4 py-2 text-sm text-primary-foreground">筛选</button>
    <Button v-if="hasActiveFilters" type="button" variant="outline" size="sm" @click="clearFilters">清除筛选</Button>
  </form>

  <div v-if="hasActiveFilters" class="mb-4 flex flex-wrap items-center gap-2 text-xs">
    <span class="text-muted-foreground">当前筛选：</span>
    <Badge v-if="query" variant="outline">关键词：{{ query }}</Badge>
    <Badge v-if="activeCategory" variant="outline">分类</Badge>
    <Badge v-if="inStock" variant="outline">仅有货</Badge>
    <Badge v-if="onSale" variant="outline">促销中</Badge>
    <Badge v-if="priceMin || priceMax" variant="outline">价格区间</Badge>
    <Badge v-if="sort && sort !== 'newest'" variant="outline">排序：{{ sort }}</Badge>
  </div>

  <div v-if="categories.length" class="mb-4 flex flex-wrap gap-2">
    <Link
      :href="routes.store"
      class="rounded-full border px-3 py-1 text-sm transition-colors"
      :class="!activeCategory ? 'border-primary bg-primary/10' : 'hover:bg-muted'"
    >
      全部
    </Link>
    <Link
      v-for="category in categories"
      :key="category.slug"
      :href="category.url"
      class="rounded-full border px-3 py-1 text-sm transition-colors"
      :class="activeCategory === category.slug ? 'border-primary bg-primary/10' : 'hover:bg-muted'"
    >
      {{ category.name }}<span v-if="category.product_count != null" class="ml-1 text-muted-foreground">({{ category.product_count }})</span>
    </Link>
  </div>

  <div v-if="products.length" class="rounded-lg border">
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>商品</TableHead>
          <TableHead>分类</TableHead>
          <TableHead>价格</TableHead>
          <TableHead>状态</TableHead>
          <TableHead class="w-24">操作</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        <TableRow v-for="product in products" :key="product.id">
          <TableCell>
            <div class="flex items-center gap-3">
              <img
                v-if="product.image_url"
                :src="product.image_url"
                :alt="product.name"
                class="h-10 w-10 rounded object-cover"
              />
              <div>
                <Link :href="product.url" class="font-medium hover:underline">
                  {{ product.name }}
                </Link>
                <p v-if="product.summary" class="mt-0.5 line-clamp-1 text-xs text-muted-foreground">{{ product.summary }}</p>
                <span v-if="product.average_rating" class="ml-2 text-xs text-amber-600">★ {{ product.average_rating }}</span>
                <span class="ml-2 text-xs text-muted-foreground">{{ product.slug }}</span>
              </div>
            </div>
          </TableCell>
          <TableCell>{{ product.category_name || '—' }}</TableCell>
          <TableCell>
            <span class="font-medium">{{ product.price_label }}</span>
            <span v-if="product.on_sale && product.compare_at_label" class="ml-2 text-xs text-muted-foreground line-through">{{ product.compare_at_label }}</span>
            <Badge v-if="product.on_sale" variant="default" class="ml-2 text-[10px]">促销</Badge>
            <Badge v-if="product.discount_label" variant="outline" class="ml-1 text-[10px]">{{ product.discount_label }}</Badge>
          </TableCell>
          <TableCell>
            <Badge v-if="!product.in_stock" variant="danger">缺货</Badge>
            <Badge v-else-if="product.low_stock" variant="outline" class="border-amber-300 text-amber-700">库存紧张</Badge>
            <Badge v-else variant="success">有货</Badge>
          </TableCell>
          <TableCell>
            <div class="flex flex-col gap-1">
              <Button
                v-if="product.quick_addable"
                type="button"
                size="sm"
                variant="outline"
                @click="quickAdd(product)"
              >
                加购
              </Button>
              <Button
                v-if="loggedIn && product.compare_url"
                type="button"
                size="sm"
                :variant="product.compared ? 'outline' : 'secondary'"
                @click="toggleCompare(product.compare_url!)"
              >
                {{ product.compared ? '对比中' : '对比' }}
              </Button>
            </div>
          </TableCell>
        </TableRow>
      </TableBody>
    </Table>
  </div>

  <p v-else class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
    暂无商品。
  </p>

  <Pagination :pagination="pagination" :base-path="routes.store" />
</template>
