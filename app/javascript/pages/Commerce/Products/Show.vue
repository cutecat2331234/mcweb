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
import Input from '@/components/ui/Input.vue'
import Textarea from '@/components/ui/Textarea.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

export interface ProductVariant {
  id: number
  name: string
  sku: string
  price_label: string
  in_stock: boolean
  low_stock: boolean
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
  low_stock: boolean
  purchase_limit: number | null
  image_url: string | null
  gallery_urls: string[]
  version?: string | null
  changelog?: string | null
  view_count?: number
  wishlisted: boolean
  average_rating: number | null
  variants: ProductVariant[]
  reviews: ProductReview[]
}

const props = defineProps<{
  product: ProductDetail
  related_products: Array<{
    id: string
    name: string
    price_label: string
    url: string
    image_url: string | null
  }>
  addToCartUrl: string
  wishlistUrl: string
  reviewUrl: string
  stockAlertUrl: string
  stockAlertSubscribed: boolean
  loggedIn: boolean
  questionUrl: string
  canAnswerOfficially: boolean
  questions: Array<{
    id: number
    body: string
    author: string
    created_at: string
    answerUrl: string
    answers: Array<{
      id: number
      body: string
      author: string
      official: boolean
      created_at: string
    }>
  }>
}>()

const questionForm = useForm({ question: { body: '' } })
const answerForms = ref<Record<number, string>>({})

const selectedVariantId = ref<number | null>(
  props.product.variants.length === 1 ? props.product.variants[0].id : null
)
const quantity = ref(1)
const galleryIndex = ref(0)

const allImages = computed(() => {
  const images: string[] = []
  if (props.product.image_url) images.push(props.product.image_url)
  images.push(...props.product.gallery_urls)
  return images
})

const activeGalleryImage = computed(() => allImages.value[galleryIndex.value] || null)

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
    quantity: quantity.value,
  })
}

function selectGalleryImage(index: number) {
  galleryIndex.value = index
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

function subscribeStockAlert() {
  router.post(props.stockAlertUrl, {
    variant_id: selectedVariantId.value,
  }, { preserveScroll: true })
}

function submitQuestion() {
  questionForm.post(props.questionUrl, {
    preserveScroll: true,
    onSuccess: () => { questionForm.question.body = '' },
  })
}

function submitAnswer(questionId: number, answerUrl: string) {
  const body = answerForms.value[questionId]
  if (!body?.trim()) return
  router.post(answerUrl, { answer: { body } }, {
    preserveScroll: true,
    onSuccess: () => { answerForms.value[questionId] = '' },
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

  <section v-if="product.version || product.changelog" class="mb-6 max-w-xl rounded-lg border p-4">
    <h2 class="mb-2 text-sm font-semibold">版本信息</h2>
    <p v-if="product.version" class="text-sm">当前版本：{{ product.version }}</p>
    <p v-if="product.changelog" class="mt-2 whitespace-pre-wrap text-sm text-muted-foreground">{{ product.changelog }}</p>
  </section>

  <div v-if="allImages.length" class="mb-6 max-w-xl">
    <img
      v-if="activeGalleryImage"
      :src="activeGalleryImage"
      :alt="product.name"
      class="mb-3 max-h-80 w-full rounded-lg border object-cover"
    />
    <div v-if="allImages.length > 1" class="flex flex-wrap gap-2">
      <button
        v-for="(url, index) in allImages"
        :key="index"
        type="button"
        class="overflow-hidden rounded border transition-opacity"
        :class="galleryIndex === index ? 'ring-2 ring-primary' : 'opacity-70 hover:opacity-100'"
        @click="selectGalleryImage(index)"
      >
        <img :src="url" :alt="`${product.name} ${index + 1}`" class="h-16 w-16 object-cover" />
      </button>
    </div>
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
            <span class="ml-1 text-xs text-muted-foreground">
              {{ !variant.in_stock ? '缺货' : variant.low_stock ? '库存紧张' : '有货' }}
            </span>
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
        <span :class="product.low_stock && canPurchase ? 'text-amber-600' : ''">
          {{ !canPurchase ? '缺货' : product.low_stock ? '库存紧张' : '有货' }}
        </span>
      </div>
      <div v-if="product.purchase_limit" class="flex justify-between text-sm">
        <span class="text-muted-foreground">限购</span>
        <span>每人最多 {{ product.purchase_limit }} 件</span>
      </div>
      <div v-if="canPurchase" class="space-y-2">
        <Label for="quantity">数量</Label>
        <Input
          id="quantity"
          v-model.number="quantity"
          type="number"
          min="1"
          :max="product.purchase_limit || 99"
          class="w-24"
        />
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
    <Button
      v-if="loggedIn && !canPurchase && !stockAlertSubscribed"
      type="button"
      variant="outline"
      :disabled="product.variants.length > 0 && !selectedVariantId"
      @click="subscribeStockAlert"
    >
      到货通知
    </Button>
    <p v-else-if="loggedIn && !canPurchase && stockAlertSubscribed" class="self-center text-sm text-muted-foreground">
      已订阅到货通知
    </p>
    <Button as-child variant="outline">
      <Link :href="routes.store">返回商城</Link>
    </Button>
  </div>

  <section class="mt-10 max-w-xl">
    <h2 class="mb-4 text-sm font-semibold">商品问答</h2>
    <div v-if="questions.length" class="mb-6 space-y-4">
      <article v-for="q in questions" :key="q.id" class="rounded-lg border p-4">
        <p class="text-sm font-medium">问：{{ q.body }}</p>
        <p class="mt-1 text-xs text-muted-foreground">{{ q.author }} · {{ q.created_at }}</p>
        <div v-if="q.answers.length" class="mt-3 space-y-2 border-l-2 pl-3">
          <div v-for="answer in q.answers" :key="answer.id" class="text-sm">
            <span v-if="answer.official" class="mr-1 rounded bg-primary/10 px-1 text-xs text-primary">官方</span>
            <span class="font-medium">{{ answer.author }}：</span>{{ answer.body }}
            <p class="text-xs text-muted-foreground">{{ answer.created_at }}</p>
          </div>
        </div>
        <form v-if="loggedIn" class="mt-3 space-y-2" @submit.prevent="submitAnswer(q.id, q.answerUrl)">
          <Textarea v-model="answerForms[q.id]" rows="2" placeholder="写下回答…" />
          <Button type="submit" size="sm" variant="outline">回答</Button>
        </form>
      </article>
    </div>
    <p v-else class="mb-4 text-sm text-muted-foreground">暂无问答，成为第一个提问的人吧。</p>
    <form v-if="loggedIn" class="space-y-3" @submit.prevent="submitQuestion">
      <Label>提问</Label>
      <Textarea v-model="questionForm.question.body" rows="3" placeholder="关于商品的问题…" />
      <Button type="submit" size="sm" :disabled="questionForm.processing">提交问题</Button>
    </form>
  </section>

  <section v-if="related_products.length" class="mt-10">
    <h2 class="mb-4 text-sm font-semibold">相关商品</h2>
    <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
      <Link
        v-for="item in related_products"
        :key="item.id"
        :href="item.url"
        class="rounded-lg border p-3 hover:bg-muted/50"
      >
        <img v-if="item.image_url" :src="item.image_url" :alt="item.name" class="mb-2 h-24 w-full rounded object-cover" />
        <p class="text-sm font-medium">{{ item.name }}</p>
        <p class="text-sm text-muted-foreground">{{ item.price_label }}</p>
      </Link>
    </div>
  </section>

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
