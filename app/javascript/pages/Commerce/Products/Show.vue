<script setup lang="ts">
import { computed, ref } from 'vue'
import { Link, router, useForm } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Pagination from '@/components/portal/Pagination.vue'
import Badge from '@/components/ui/Badge.vue'
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
  helpful_count?: number
  helpful?: boolean
  helpful_url?: string | null
  report_url?: string | null
  verified_purchaser?: boolean
  can_share_to_forum?: boolean
  share_to_forum_url?: string | null
  forum_post_url?: string | null
  photo_urls?: string[]
}

export interface ProductDetail {
  id: string
  db_id: number
  name: string
  slug: string
  description: string | null
  price_label: string
  compare_at_label?: string | null
  on_sale?: boolean
  discount_percent?: number | null
  discount_label?: string | null
  purchased?: boolean
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
  saved_variant_id?: number | null
  average_rating: number | null
  variants: ProductVariant[]
  reviews: ProductReview[]
  discussion_url?: string | null
  discussion_replies_count?: number | null
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
  compareUrl?: string
  compared?: boolean
  compareCount?: number
  reviewUrl: string
  stockAlertUrl: string
  stockAlertVariantIds?: Array<number | null>
  stockAlertUnsubscribeUrls?: Array<{ variant_id: number | null; unsubscribe_url: string }>
  priceAlertUrl?: string | null
  hasPriceAlert?: boolean
  createDiscussionUrl?: string | null
  askFromOrder?: { order_number: string; item_name: string; order_item_id: number } | null
  canReview?: boolean
  canEditReview?: boolean
  canDeleteReview?: boolean
  deleteReviewUrl?: string | null
  reorderUrl?: string | null
  userReview?: ProductReview | null
  ratingBreakdown?: Array<{ rating: number; count: number }>
  reviewSort?: string
  reviewRating?: number | null
  reviewsCount?: number
  reviewsPagination?: import('@/components/portal/Pagination.vue').PaginationMeta
  questionSort?: string
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
      helpful_count?: number
      helpful?: boolean
      helpful_url?: string | null
    }>
    from_order?: boolean
  }>
  questionsPagination?: import('@/components/portal/Pagination.vue').PaginationMeta
  questionQuery?: string
}>()

const questionForm = useForm({ question: { body: '' } })
const answerForms = ref<Record<number, string>>({})

const selectedVariantId = ref<number | null>(
  props.product.variants.length === 1 ? props.product.variants[0].id : (props.product.saved_variant_id ?? null)
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

const reviewForm = useForm<{
  review: { rating: number; body: string; photos: File[] }
}>({
  review: { rating: 5, body: '', photos: [] },
})
const editingReview = ref(false)
const existingReviewPhotos = ref<string[]>([])

function onReviewPhotosChange(event: Event) {
  const input = event.target as HTMLInputElement
  reviewForm.review.photos = Array.from(input.files || []).slice(0, 3)
}

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

const showLowStock = computed(() => {
  if (selectedVariant.value) {
    return selectedVariant.value.low_stock && selectedVariant.value.in_stock
  }
  return props.product.low_stock && props.product.in_stock
})

const wishlistedForSelection = computed(() => {
  if (!props.product.wishlisted) return false
  if (!props.product.saved_variant_id) return true
  if (!selectedVariantId.value) return true
  return props.product.saved_variant_id === selectedVariantId.value
})

const ratingBreakdownMax = computed(() => {
  const counts = props.ratingBreakdown?.map((entry) => entry.count) || []
  return Math.max(...counts, 1)
})

const stockAlertSubscribed = computed(() => {
  const variantId = selectedVariantId.value ?? null
  return props.stockAlertVariantIds?.some((id) => id === variantId) ?? false
})

const stockAlertUnsubscribeUrl = computed(() => {
  const variantId = selectedVariantId.value ?? null
  return props.stockAlertUnsubscribeUrls?.find((entry) => entry.variant_id === variantId)?.unsubscribe_url
})

const reviewSort = ref(props.reviewSort || 'newest')

const reviewRating = ref<number | ''>(props.reviewRating || '')
const questionSearch = ref(props.questionQuery || '')

function searchQuestions() {
  router.get(routes.storeProduct(props.product.id), {
    question_q: questionSearch.value || undefined,
    question_page: undefined,
  }, { preserveScroll: true, preserveState: true })
}

function changeReviewSort(value: string) {
  reviewSort.value = value
  router.get(routes.storeProduct(props.product.id), {
    review_sort: value !== 'newest' ? value : undefined,
    review_rating: reviewRating.value || undefined,
  }, { preserveScroll: true, preserveState: true })
}

function changeReviewRating(value: string) {
  reviewRating.value = value ? Number(value) : ''
  router.get(routes.storeProduct(props.product.id), {
    review_sort: reviewSort.value !== 'newest' ? reviewSort.value : undefined,
    review_rating: reviewRating.value || undefined,
  }, { preserveScroll: true, preserveState: true })
}

function toggleHelpful(url: string | null | undefined) {
  if (!url) return
  router.post(url, {}, { preserveScroll: true })
}

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
  router.post(props.wishlistUrl, {
    variant_id: selectedVariantId.value || undefined,
  }, { preserveScroll: true })
}

function toggleCompare() {
  if (!props.compareUrl) return
  router.post(props.compareUrl, {}, { preserveScroll: true })
}

function startEditReview() {
  if (!props.userReview) return
  reviewForm.review.rating = props.userReview.rating
  reviewForm.review.body = props.userReview.body || ''
  existingReviewPhotos.value = props.userReview.photo_urls || []
  editingReview.value = true
}

function deleteReview() {
  if (!props.deleteReviewUrl || !confirm('确定删除你的评价？')) return
  router.delete(props.deleteReviewUrl)
}

function loadMoreReviews() {
  const nextPage = (props.reviewsPagination?.page || 1) + 1
  if (!props.reviewsPagination || nextPage > props.reviewsPagination.pages) return
  router.get(routes.storeProduct(props.product.id), {
    review_page: nextPage,
    review_sort: reviewSort.value !== 'newest' ? reviewSort.value : undefined,
    review_rating: reviewRating.value || undefined,
  }, { preserveScroll: true, preserveState: true, only: ['product', 'reviewsPagination', 'reviewsCount'] })
}

function submitReview() {
  reviewForm.post(props.reviewUrl, {
    preserveScroll: true,
    forceFormData: true,
    onSuccess: () => {
      reviewForm.review.body = ''
      reviewForm.review.photos = []
      existingReviewPhotos.value = []
      editingReview.value = false
    },
  })
}

function subscribeStockAlert() {
  if (props.product.variants.length > 0 && !selectedVariantId.value) return
  router.post(props.stockAlertUrl, {
    variant_id: selectedVariantId.value,
  }, { preserveScroll: true })
}

function unsubscribeStockAlert() {
  const url = stockAlertUnsubscribeUrl.value
  if (!url) return
  router.delete(url, { preserveScroll: true })
}

function togglePriceAlert() {
  if (!props.priceAlertUrl) return
  router.post(props.priceAlertUrl, {
    variant_id: selectedVariantId.value,
  }, { preserveScroll: true })
}

function createDiscussion() {
  if (!props.createDiscussionUrl) return
  router.post(props.createDiscussionUrl)
}

function shareReviewToForum(url: string) {
  router.post(url)
}

function filterByRating(rating: number) {
  router.get(routes.storeProduct(props.product.id), {
    review_rating: rating,
    review_sort: reviewSort.value !== 'newest' ? reviewSort.value : undefined,
  }, { preserveScroll: true, preserveState: true })
}

function submitQuestion() {
  questionForm.transform((data) => ({
    ...data,
    order_item_id: props.askFromOrder?.order_item_id,
  })).post(props.questionUrl, {
    preserveScroll: true,
    onSuccess: () => { questionForm.question.body = '' },
  })
}

function toggleAnswerHelpful(url: string) {
  router.post(url, {}, { preserveScroll: true })
}

function changeQuestionSort(value: string) {
  router.get(routes.storeProduct(props.product.id), {
    question_sort: value !== 'newest' ? value : undefined,
    question_q: questionSearch.value || undefined,
  }, { preserveScroll: true, preserveState: true })
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
  <div v-if="product.purchased" class="mb-4 flex flex-wrap items-center gap-2">
    <Badge variant="default">你已购买此商品</Badge>
    <Button v-if="reorderUrl" type="button" size="sm" variant="outline" @click="router.post(reorderUrl)">再次购买</Button>
  </div>

  <section v-if="product.version || product.changelog" class="mb-6 max-w-xl rounded-lg border p-4">
    <h2 class="mb-2 text-sm font-semibold">版本信息</h2>
    <p v-if="product.version" class="text-sm">当前版本：{{ product.version }}</p>
    <p v-if="product.changelog" class="mt-2 whitespace-pre-wrap text-sm text-muted-foreground">{{ product.changelog }}</p>
  </section>

  <section v-if="product.discussion_url || createDiscussionUrl" class="mb-6 max-w-xl rounded-lg border p-4">
    <h2 class="mb-2 text-sm font-semibold">社区讨论</h2>
    <p v-if="product.discussion_replies_count !== null && product.discussion_replies_count !== undefined" class="text-sm text-muted-foreground">
      {{ product.discussion_replies_count }} 条回复
    </p>
    <div class="mt-2 flex gap-2">
      <Button v-if="product.discussion_url" as-child size="sm">
        <Link :href="product.discussion_url">参与讨论</Link>
      </Button>
      <Button v-else-if="createDiscussionUrl" type="button" size="sm" variant="outline" @click="createDiscussion">
        开启讨论帖
      </Button>
    </div>
  </section>

  <p v-if="askFromOrder" class="mb-4 rounded-md border border-blue-200 bg-blue-50 px-4 py-3 text-sm text-blue-900">
    关于订单 {{ askFromOrder.order_number }} 的商品「{{ askFromOrder.item_name }}」提问
  </p>

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
        <span class="text-amber-500">★</span> {{ product.average_rating }} / 5（{{ reviewsCount ?? product.reviews.length }} 条评价）
      </div>
      <div v-if="product.view_count" class="text-sm text-muted-foreground">
        {{ product.view_count }} 次浏览
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
        <span class="font-medium">
          {{ displayPrice }}
          <span v-if="product.on_sale && product.compare_at_label" class="ml-2 text-xs font-normal text-muted-foreground line-through">{{ product.compare_at_label }}</span>
          <Badge v-if="product.on_sale" variant="default" class="ml-2 text-[10px]">促销</Badge>
          <Badge v-if="product.discount_label" variant="outline" class="ml-1 text-[10px]">{{ product.discount_label }}</Badge>
        </span>
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
        <span :class="showLowStock ? 'text-amber-600' : ''">
          {{ !canPurchase ? '缺货' : showLowStock ? '库存紧张' : '有货' }}
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
      {{ wishlistedForSelection ? '移出心愿单' : '加入心愿单' }}
    </Button>
    <Button
      v-if="loggedIn && priceAlertUrl"
      type="button"
      variant="outline"
      @click="togglePriceAlert"
    >
      {{ hasPriceAlert ? '已订阅降价' : '降价提醒' }}
    </Button>
    <Button v-if="compareUrl" type="button" variant="outline" @click="toggleCompare">
      {{ compared ? '移出对比' : '加入对比' }}{{ compareCount ? ` (${compareCount})` : '' }}
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
    <p v-else-if="loggedIn && !canPurchase && stockAlertSubscribed" class="flex items-center gap-2 self-center text-sm text-muted-foreground">
      已订阅到货通知
      <Button v-if="stockAlertUnsubscribeUrl" type="button" variant="outline" size="sm" @click="unsubscribeStockAlert">取消订阅</Button>
    </p>
    <Button as-child variant="outline">
      <Link :href="routes.store">返回商城</Link>
    </Button>
  </div>

  <section class="mt-10 max-w-xl">
    <div class="mb-4 flex flex-wrap items-center justify-between gap-2">
      <h2 class="text-sm font-semibold">商品问答</h2>
      <div class="flex flex-wrap items-center gap-2">
        <select
          v-if="questions.length"
          :value="questionSort || 'newest'"
          class="h-8 rounded-md border px-2 text-xs"
          @change="changeQuestionSort(($event.target as HTMLSelectElement).value)"
        >
          <option value="newest">最新回答</option>
          <option value="helpful">最有帮助</option>
        </select>
        <form class="flex gap-2" @submit.prevent="searchQuestions">
          <Input v-model="questionSearch" placeholder="搜索问答…" class="h-8 max-w-xs text-sm" />
          <Button type="submit" size="sm" variant="outline">搜索</Button>
        </form>
      </div>
    </div>
    <div v-if="questions.length" class="mb-6 space-y-4">
      <article v-for="q in questions" :key="q.id" class="rounded-lg border p-4">
        <p class="text-sm font-medium">
          问：{{ q.body }}
          <Badge v-if="q.from_order" class="ml-2 text-[10px]">已购提问</Badge>
        </p>
        <p class="mt-1 text-xs text-muted-foreground">{{ q.author }} · {{ q.created_at }}</p>
        <div v-if="q.answers.length" class="mt-3 space-y-2 border-l-2 pl-3">
          <div v-for="answer in q.answers" :key="answer.id" class="text-sm">
            <span v-if="answer.official" class="mr-1 rounded bg-primary/10 px-1 text-xs text-primary">官方</span>
            <span class="font-medium">{{ answer.author }}：</span>{{ answer.body }}
            <p class="text-xs text-muted-foreground">{{ answer.created_at }}</p>
            <div v-if="answer.helpful_url" class="mt-1">
              <Button
                type="button"
                size="sm"
                variant="outline"
                :class="answer.helpful ? 'border-primary text-primary' : ''"
                @click="toggleAnswerHelpful(answer.helpful_url!)"
              >
                有帮助 ({{ answer.helpful_count || 0 }})
              </Button>
            </div>
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
    <Pagination
      v-if="questionsPagination && questionsPagination.pages > 1"
      class="mt-4"
      :pagination="questionsPagination"
      :base-path="routes.storeProduct(product.id)"
      :page-param="'question_page'"
    />
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

  <section v-if="product.reviews.length || userReview || ratingBreakdown?.length" class="mt-10 max-w-xl">
    <div class="mb-4 flex flex-wrap items-center justify-between gap-2">
      <h2 class="text-sm font-semibold">用户评价</h2>
      <select
        v-if="product.reviews.length || reviewsCount"
        :value="reviewSort"
        class="h-8 rounded-md border px-2 text-xs"
        @change="changeReviewSort(($event.target as HTMLSelectElement).value)"
      >
        <option value="newest">最新</option>
        <option value="helpful">最有帮助</option>
        <option value="rating">评分最高</option>
      </select>
      <select
        :value="reviewRating"
        class="h-8 rounded-md border px-2 text-xs"
        @change="changeReviewRating(($event.target as HTMLSelectElement).value)"
      >
        <option value="">全部星级</option>
        <option v-for="n in 5" :key="n" :value="n">{{ n }} 星</option>
      </select>
    </div>
    <div v-if="ratingBreakdown?.length" class="mb-4 space-y-1">
      <button
        v-for="entry in [...ratingBreakdown].sort((a, b) => b.rating - a.rating)"
        :key="entry.rating"
        type="button"
        class="flex w-full items-center gap-2 text-xs hover:opacity-80"
        @click="filterByRating(entry.rating)"
      >
        <span class="w-8">{{ entry.rating }} 星</span>
        <div class="h-2 flex-1 overflow-hidden rounded bg-muted">
          <div class="h-full bg-amber-400" :style="{ width: `${(entry.count / ratingBreakdownMax) * 100}%` }" />
        </div>
        <span class="w-8 text-muted-foreground">{{ entry.count }}</span>
      </button>
    </div>
    <div v-if="userReview && !editingReview" class="mb-4 rounded-lg border border-primary/30 bg-primary/5 p-4">
      <div class="mb-2 flex items-center justify-between">
        <p class="text-sm font-medium">你的评价</p>
        <div class="flex gap-2">
          <Button v-if="userReview.can_share_to_forum && userReview.share_to_forum_url" type="button" size="sm" variant="outline" @click="shareReviewToForum(userReview.share_to_forum_url!)">分享到论坛</Button>
          <Button v-if="userReview.forum_post_url" as-child size="sm" variant="outline">
            <Link :href="userReview.forum_post_url">查看论坛帖</Link>
          </Button>
          <Button v-if="canEditReview" type="button" size="sm" variant="outline" @click="startEditReview">编辑</Button>
          <Button v-if="canDeleteReview" type="button" size="sm" variant="destructive" @click="deleteReview">删除</Button>
        </div>
      </div>
      <div class="mb-1 flex items-center justify-between text-sm">
        <span class="text-amber-500">{{ '★'.repeat(userReview.rating) }}</span>
        <span class="text-xs text-muted-foreground">{{ userReview.created_at }}</span>
      </div>
      <p v-if="userReview.body" class="text-sm">{{ userReview.body }}</p>
      <div v-if="userReview.photo_urls?.length" class="mt-2 flex flex-wrap gap-2">
        <img v-for="(url, i) in userReview.photo_urls" :key="i" :src="url" alt="" class="h-20 w-20 rounded object-cover" />
      </div>
    </div>
    <div class="space-y-3">
      <article v-for="review in product.reviews" :key="review.id" class="rounded-lg border p-4">
        <div class="mb-1 flex items-center justify-between text-sm">
          <span class="font-medium">
            {{ review.author }}
            <Badge v-if="review.verified_purchaser" variant="default" class="ml-2 text-[10px]">已购</Badge>
          </span>
          <span class="text-amber-500">{{ '★'.repeat(review.rating) }}</span>
        </div>
        <p v-if="review.body" class="text-sm">{{ review.body }}</p>
        <div v-if="review.photo_urls?.length" class="mt-2 flex flex-wrap gap-2">
          <a v-for="(url, i) in review.photo_urls" :key="i" :href="url" target="_blank" rel="noopener">
            <img :src="url" alt="" class="h-20 w-20 rounded object-cover ring-1 ring-border hover:opacity-90" />
          </a>
        </div>
        <div class="mt-2 flex items-center justify-between gap-2">
          <p class="text-xs text-muted-foreground">{{ review.created_at }}</p>
          <div class="flex gap-2">
            <Button
              v-if="loggedIn && review.helpful_url"
              type="button"
              variant="outline"
              size="sm"
              :class="review.helpful ? 'border-primary' : ''"
              @click="toggleHelpful(review.helpful_url)"
            >
              有帮助{{ review.helpful_count ? ` (${review.helpful_count})` : '' }}
            </Button>
            <Button v-if="review.report_url" as-child variant="ghost" size="sm">
              <Link :href="review.report_url">举报</Link>
            </Button>
          </div>
        </div>
      </article>
    </div>
    <Pagination v-if="reviewsPagination" :pagination="reviewsPagination" :base-path="routes.storeProduct(product.id)" query-param="review_page" />
    <Button
      v-if="reviewsPagination && reviewsPagination.page < reviewsPagination.pages"
      type="button"
      variant="outline"
      class="mt-3"
      @click="loadMoreReviews"
    >
      加载更多评价
    </Button>
  </section>

  <section v-if="loggedIn && (canReview || (canEditReview && editingReview))" class="mt-8 max-w-xl">
    <h2 class="mb-3 text-sm font-semibold">{{ canEditReview ? '编辑评价' : '写评价' }}</h2>
    <form class="space-y-3" @submit.prevent="submitReview">
      <div class="space-y-2">
        <Label>评分</Label>
        <select v-model.number="reviewForm.review.rating" class="h-9 rounded-md border px-2 text-sm">
          <option v-for="n in 5" :key="n" :value="n">{{ n }} 星</option>
        </select>
      </div>
      <Textarea v-model="reviewForm.review.body" rows="4" placeholder="分享你的使用体验（可选）" />
      <div v-if="existingReviewPhotos.length" class="space-y-2">
        <Label>当前图片（不上传新图则保留）</Label>
        <div class="flex flex-wrap gap-2">
          <a v-for="(url, i) in existingReviewPhotos" :key="i" :href="url" target="_blank" rel="noopener">
            <img :src="url" alt="" class="h-20 w-20 rounded object-cover ring-1 ring-border" />
          </a>
        </div>
      </div>
      <div class="space-y-2">
        <Label for="review_photos">图片（最多 3 张）</Label>
        <Input id="review_photos" type="file" accept="image/*" multiple @change="onReviewPhotosChange" />
      </div>
      <Button type="submit" :disabled="reviewForm.processing">提交评价</Button>
    </form>
  </section>
</template>
