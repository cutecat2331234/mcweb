<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Badge from '@/components/ui/Badge.vue'
import Button from '@/components/ui/Button.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

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
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.store'), href: routes.store },
    { label: t('commerce.wishlistPublic.breadcrumb'), current: true },
  ]" />

  <PageHeader :title="t('commerce.wishlistPublic.title', { owner })" :subtitle="t('commerce.wishlistPublic.subtitle')" />

  <div v-if="hasActiveFilters()" class="mb-4 flex flex-wrap items-center gap-2 text-xs">
    <span class="text-muted-foreground">{{ t('commerce.wishlistPublic.activeFilters') }}</span>
    <Badge v-if="filters?.in_stock" variant="outline">{{ t('commerce.wishlistPublic.inStock') }}</Badge>
    <Badge v-if="filters?.on_sale" variant="outline">{{ t('commerce.wishlistPublic.onSale') }}</Badge>
    <Badge v-if="filters?.coming_soon" variant="outline">{{ t('commerce.wishlistPublic.comingSoon') }}</Badge>
    <Badge v-if="filters?.sort && filters.sort !== 'newest'" variant="outline">{{ filters.sort }}</Badge>
    <span v-if="totalCount !== undefined && filteredCount !== undefined" class="text-muted-foreground">
      {{ t('commerce.wishlistPublic.showingCount', { filtered: filteredCount, total: totalCount }) }}
    </span>
  </div>

  <div v-if="products.length" class="divide-y rounded-lg border">
    <div v-for="product in products" :key="product.id" class="flex items-center justify-between p-4">
      <div>
        <Link :href="product.url" class="font-medium hover:underline">{{ product.name }}</Link>
        <Badge v-if="product.coming_soon" variant="outline" class="ml-2 text-[10px]">{{ t('commerce.wishlistPublic.comingSoon') }}</Badge>
        <p class="text-sm">
          <span>{{ product.price_label }}</span>
          <span v-if="product.on_sale && product.compare_at_label" class="ml-2 text-xs text-muted-foreground line-through">{{ product.compare_at_label }}</span>
        </p>
        <p v-if="product.saved_variant_name" class="text-xs text-muted-foreground">{{ t('commerce.wishlistPublic.variant', { name: product.saved_variant_name }) }}</p>
        <p v-if="product.note" class="text-xs text-muted-foreground">{{ t('commerce.wishlistPublic.note', { note: product.note }) }}</p>
        <p v-if="product.coming_soon && product.available_at_label" class="text-xs text-muted-foreground">{{ t('commerce.wishlistPublic.availableAt', { at: product.available_at_label }) }}</p>
        <p v-if="product.coming_soon_label" class="text-xs text-amber-700">{{ product.coming_soon_label }}</p>
      </div>
      <Button as-child variant="outline" size="sm">
        <Link :href="product.url">{{ product.coming_soon ? t('commerce.wishlistPublic.preview') : t('commerce.wishlistPublic.view') }}</Link>
      </Button>
    </div>
  </div>
  <p v-else class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
    {{ hasActiveFilters() ? t('commerce.wishlistPublic.emptyFiltered') : t('commerce.wishlistPublic.empty') }}
  </p>
</template>
