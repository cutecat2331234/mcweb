<script setup lang="ts">
import { computed } from 'vue'
import { Link } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

const props = defineProps<{
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

const stockLabel = (inStock: boolean) => inStock ? t('commerce.compare.inStock') : t('commerce.compare.outOfStock')

const rows = computed(() => [
  { key: 'price', label: t('commerce.compare.price'), get: (p: (typeof props)['products'][number]) => p.price_label },
  { key: 'category', label: t('commerce.compare.category'), get: (p: (typeof props)['products'][number]) => p.category_name || '—' },
  { key: 'stock', label: t('commerce.compare.stock'), get: (p: (typeof props)['products'][number]) => stockLabel(p.in_stock) },
  { key: 'rating', label: t('commerce.compare.rating'), get: (p: (typeof props)['products'][number]) => String(p.average_rating ?? '—') },
])
</script>

<template>
  <Breadcrumb :items="[
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.store'), href: routes.store },
    { label: t('commerce.compare.publicBreadcrumb'), current: true },
  ]" />

  <PageHeader :title="t('commerce.compare.publicTitle', { owner })" :subtitle="t('commerce.compare.publicSubtitle')" />

  <div v-if="products.length" class="overflow-x-auto">
    <table class="w-full min-w-[640px] border text-sm">
      <thead>
        <tr class="border-b bg-muted/50">
          <th class="p-3 text-left">{{ t('commerce.compare.attribute') }}</th>
          <th v-for="product in products" :key="product.id" class="p-3 text-left">
            <Link :href="product.url" class="font-medium hover:underline">{{ product.name }}</Link>
          </th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="row in rows" :key="row.key" class="border-b">
          <td class="p-3 text-muted-foreground">{{ row.label }}</td>
          <td v-for="product in products" :key="`${product.id}-${row.key}`" class="p-3">{{ row.get(product) }}</td>
        </tr>
      </tbody>
    </table>
  </div>
  <p v-else class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
    {{ t('commerce.compare.publicEmpty') }}
  </p>

  <div class="mt-4">
    <Button as-child variant="outline">
      <Link :href="routes.storeCompare">{{ t('commerce.compare.createOwn') }}</Link>
    </Button>
  </div>
</template>
