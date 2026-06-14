<script setup lang="ts">
import { computed, ref } from 'vue'
import { Link, router } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Card from '@/components/ui/Card.vue'
import CardContent from '@/components/ui/CardContent.vue'
import Label from '@/components/ui/Label.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

export interface ProductVariant {
  id: number
  name: string
  sku: string
  price_label: string
  in_stock: boolean
}

export interface ProductDetail {
  id: string
  db_id: number
  name: string
  slug: string
  description: string | null
  price_label: string
  product_type: string
  category_name: string | null
  in_stock: boolean
  purchase_limit: number | null
  variants: ProductVariant[]
}

const props = defineProps<{
  product: ProductDetail
  addToCartUrl: string
}>()

const selectedVariantId = ref<number | null>(
  props.product.variants.length === 1 ? props.product.variants[0].id : null
)

const selectedVariant = computed(() =>
  props.product.variants.find((variant) => variant.id === selectedVariantId.value) || null
)

const displayPrice = computed(() => selectedVariant.value?.price_label || props.product.price_label)

const canPurchase = computed(() => {
  if (props.product.variants.length > 0) {
    return selectedVariant.value?.in_stock ?? false
  }
  return props.product.in_stock
})

function addToCart() {
  router.patch(props.addToCartUrl, {
    product_id: props.product.db_id,
    variant_id: selectedVariantId.value,
    quantity: 1,
  })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '商城', href: routes.store },
    { label: product.name, current: true },
  ]" />

  <PageHeader :title="product.name" :subtitle="product.description || undefined" />

  <Card class="max-w-xl">
    <CardContent class="space-y-3 pt-6">
      <div v-if="product.variants.length" class="space-y-2">
        <Label>规格</Label>
        <div class="flex flex-wrap gap-2">
          <button
            v-for="variant in product.variants"
            :key="variant.id"
            type="button"
            class="rounded-md border px-3 py-1.5 text-sm transition-colors"
            :class="selectedVariantId === variant.id ? 'border-primary bg-primary/10' : 'hover:bg-muted'"
            @click="selectedVariantId = variant.id"
          >
            {{ variant.name }} · {{ variant.price_label }}
            <span class="ml-1 text-xs text-muted-foreground">{{ variant.in_stock ? '有货' : '缺货' }}</span>
          </button>
        </div>
      </div>

      <div class="flex justify-between text-sm">
        <span class="text-muted-foreground">价格</span>
        <span class="font-medium">{{ displayPrice }}</span>
      </div>
      <div class="flex justify-between text-sm">
        <span class="text-muted-foreground">类型</span>
        <span>{{ product.product_type }}</span>
      </div>
      <div class="flex justify-between text-sm">
        <span class="text-muted-foreground">分类</span>
        <span>{{ product.category_name || '—' }}</span>
      </div>
      <div class="flex justify-between text-sm">
        <span class="text-muted-foreground">库存</span>
        <span>{{ canPurchase ? '有货' : '缺货' }}</span>
      </div>
      <div v-if="product.purchase_limit" class="flex justify-between text-sm">
        <span class="text-muted-foreground">限购</span>
        <span>每人最多 {{ product.purchase_limit }} 件</span>
      </div>
    </CardContent>
  </Card>

  <div class="mt-6 flex gap-3">
    <Button
      v-if="canPurchase"
      type="button"
      :disabled="product.variants.length > 0 && !selectedVariantId"
      @click="addToCart"
    >
      加入购物车
    </Button>
    <Button as-child variant="outline">
      <Link :href="routes.store">返回商城</Link>
    </Button>
  </div>
</template>
