<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import Badge from '@/components/ui/Badge.vue'
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
  url: string
}

defineProps<{
  products: ProductItem[]
  pagination: PaginationMeta
}>()
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '商城', current: true },
  ]" />

  <PageHeader title="商品列表" subtitle="浏览可购买的数字商品" />

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
            <Link :href="product.url" class="font-medium hover:underline">
              {{ product.name }}
            </Link>
            <span class="ml-2 text-xs text-muted-foreground">{{ product.slug }}</span>
          </TableCell>
          <TableCell>{{ product.category_name || '—' }}</TableCell>
          <TableCell>{{ product.price_label }}</TableCell>
          <TableCell>
            <Badge :variant="product.in_stock ? 'success' : 'danger'">
              {{ product.in_stock ? '有货' : '缺货' }}
            </Badge>
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
