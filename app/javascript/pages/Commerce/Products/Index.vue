<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import { ref } from 'vue'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import Badge from '@/components/ui/Badge.vue'
import Input from '@/components/ui/Input.vue'
import Table from '@/components/ui/Table.vue'
import TableBody from '@/components/ui/TableBody.vue'
import TableCell from '@/components/ui/TableCell.vue'
import TableHead from '@/components/ui/TableHead.vue'
import TableHeader from '@/components/ui/TableHeader.vue'
import TableRow from '@/components/ui/TableRow.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

export interface ProductItem {
  id: string
  name: string
  slug: string
  category_name: string | null
  price_label: string
  in_stock: boolean
  low_stock: boolean
  image_url: string | null
  url: string
}

export interface CategoryItem {
  slug: string
  name: string
  url: string
}

const props = defineProps<{
  products: ProductItem[]
  featured_products?: ProductItem[]
  categories: CategoryItem[]
  activeCategory: string | null
  query: string
  sort: string
  pagination: PaginationMeta
}>()

const q = ref(props.query)
const sort = ref(props.sort)

function search() {
  router.get(routes.store, {
    q: q.value || undefined,
    sort: sort.value !== 'newest' ? sort.value : undefined,
    category: props.activeCategory || undefined,
  }, { preserveState: true })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '商城', current: true },
  ]" />

  <PageHeader title="商品列表" subtitle="浏览可购买的数字商品" />

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
    <Input v-model="q" placeholder="搜索商品…" class="max-w-xs" />
    <select v-model="sort" class="h-9 rounded-md border border-input bg-transparent px-3 text-sm">
      <option value="newest">最新</option>
      <option value="popular">最热</option>
      <option value="rating">评分最高</option>
      <option value="price_asc">价格升序</option>
      <option value="price_desc">价格降序</option>
    </select>
    <button type="submit" class="rounded-md bg-primary px-4 py-2 text-sm text-primary-foreground">筛选</button>
  </form>

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
      {{ category.name }}
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
                <span class="ml-2 text-xs text-muted-foreground">{{ product.slug }}</span>
              </div>
            </div>
          </TableCell>
          <TableCell>{{ product.category_name || '—' }}</TableCell>
          <TableCell>{{ product.price_label }}</TableCell>
          <TableCell>
            <Badge v-if="!product.in_stock" variant="danger">缺货</Badge>
            <Badge v-else-if="product.low_stock" variant="outline" class="border-amber-300 text-amber-700">库存紧张</Badge>
            <Badge v-else variant="success">有货</Badge>
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
