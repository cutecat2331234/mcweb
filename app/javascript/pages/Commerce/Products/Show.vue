<script setup lang="ts">
import { computed, ref } from 'vue'
import { Link, router, useForm } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Card from '@/components/ui/Card.vue'
import CardContent from '@/components/ui/CardContent.vue'
import Label from '@/components/ui/Label.vue'
import Textarea from '@/components/ui/Textarea.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

export interface ProductVariant {
  id: number
  name: string
  sku: string
  price_label: string
  in_stock: boolean
}

export interface ProductReview {
  id: number
  author: string
  rating: number
  body: string | null
  created_at: string
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
  image_url: string | null
  gallery_urls: string[]
  wishlisted: boolean
  average_rating: number | null
  variants: ProductVariant[]
  reviews: ProductReview[]
}

const props = defineProps<{
  product: ProductDetail
  addToCartUrl: string
  wishlistUrl: string
  reviewUrl: string
  loggedIn: boolean
}>()

const selectedVariantId = ref<number | null>(
  props.product.variants.length === 1 ? props.product.variants[0].id : null
)

const reviewForm = useForm({
  review: { rating: 5, body: '' },
})

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

function toggleWishlist() {
  router.post(props.wishlistUrl, {}, { preserveScroll: true })
}

function submitReview() {
  reviewForm.post(props.reviewUrl, {
    preserveScroll: true,
    onSuccess: () => { reviewForm.review.body = '' },
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

  <img
    v-if="product.image_url"
    :src="product.image_url"
    :alt="product.name"
    class="mb-4 max-h-64 rounded-lg border object-cover"
  />

  <div v-if="product.gallery_urls.length" class="mb-6 flex flex-wrap gap-2">
    <img
      v-for="(url, index) in product.gallery_urls"
      :key="index"
      :src="url"
      :alt="`${product.name} ${index + 1}`"
      class="h-20 w-20 rounded border object-cover"
    />
  </div>

  <Card class="max-w-xl">
    <CardContent class="space-y-3 pt-6">
      <div v-if="product.average_rating" class="text-sm">
        <span class="text-amber-500">★</span> {{ product.average_rating }} / 5（{{ product.reviews.length }} 条评价）
      </div>

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

  <div class="mt-6 flex flex-wrap gap-3">
    <Button
      v-if="canPurchase"
      type="button"
      :disabled="product.variants.length > 0 && !selectedVariantId"
      @click="addToCart"
    >
      加入购物车
    </Button>
    <Button v-if="loggedIn" type="button" variant="outline" @click="toggleWishlist">
      {{ product.wishlisted ? '移出心愿单' : '加入心愿单' }}
    </Button>
    <Button as-child variant="outline">
      <Link :href="routes.store">返回商城</Link>
    </Button>
  </div>

  <section v-if="product.reviews.length" class="mt-10 max-w-xl">
    <h2 class="mb-4 text-sm font-semibold">用户评价</h2>
    <div class="space-y-3">
      <article v-for="review in product.reviews" :key="review.id" class="rounded-lg border p-4">
        <div class="mb-1 flex items-center justify-between text-sm">
          <span class="font-medium">{{ review.author }}</span>
          <span class="text-amber-500">{{ '★'.repeat(review.rating) }}</span>
        </div>
        <p v-if="review.body" class="text-sm">{{ review.body }}</p>
        <p class="mt-1 text-xs text-muted-foreground">{{ review.created_at }}</p>
      </article>
    </div>
  </section>

  <section v-if="loggedIn" class="mt-8 max-w-xl">
    <h2 class="mb-3 text-sm font-semibold">写评价</h2>
    <form class="space-y-3" @submit.prevent="submitReview">
      <div class="space-y-2">
        <Label>评分</Label>
        <select v-model.number="reviewForm.review.rating" class="h-9 rounded-md border px-2 text-sm">
          <option v-for="n in 5" :key="n" :value="n">{{ n }} 星</option>
        </select>
      </div>
      <Textarea v-model="reviewForm.review.body" rows="4" placeholder="分享你的使用体验（可选）" />
      <Button type="submit" :disabled="reviewForm.processing">提交评价</Button>
    </form>
  </section>
</template>
