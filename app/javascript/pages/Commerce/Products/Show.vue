<script setup lang="ts">
import { computed, ref, onMounted, onUnmounted } from 'vue'
import { Head, Link, router, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
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
import FileInput from '@/components/ui/FileInput.vue'
import Textarea from '@/components/ui/Textarea.vue'
import Select from '@/components/ui/Select.vue'
import { routes } from '@/lib/routes'
import { confirm } from '@/lib/useConfirm'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

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
  merchant_reply?: string | null
  merchant_replied_at?: string | null
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
  membership_type_label?: string | null
  purchase_blocked?: boolean
  prerequisite_message?: string | null
  category_name: string | null
  in_stock: boolean
  backorder_available?: boolean
  low_stock: boolean
  purchase_limit: number | null
  minimum_quantity?: number
  maximum_quantity?: number | null
  seo_title?: string
  seo_description?: string | null
  seo_image?: string | null
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

const productTypeLabel = computed(() => {
  const type = props.product.product_type
  if (!type) return '—'
  const key = `commerce.product.productTypes.${type}`
  const label = t(key)
  return label === key ? type : label
})

const stockStatusLabel = computed(() => {
  if (props.product.backorder_available) return t('commerce.product.backorder')
  if (props.product.purchase_blocked) return t('commerce.product.prerequisiteRequired')
  if (!canPurchase.value) return t('commerce.product.outOfStock')
  if (showLowStock.value) return t('commerce.product.lowStock')
  return t('commerce.product.inStock')
})

const activeGalleryImage = computed(() => allImages.value[galleryIndex.value] || null)

const reviewForm = useForm<{
  review: { rating: number; body: string; photos: File[] }
}>({
  review: { rating: 5, body: '', photos: [] },
})
const editingReview = ref(false)
const existingReviewPhotos = ref<string[]>([])

function onReviewPhotosChange(files: File | File[]) {
  const list = Array.isArray(files) ? files : [files]
  reviewForm.review.photos = list.slice(0, 3)
}

const selectedVariant = computed(() =>
  props.product.variants.find((variant) => variant.id === selectedVariantId.value) || null
)

const displayPrice = computed(() => selectedVariant.value?.price_label || props.product.price_label)

const canPurchase = computed(() => {
  if (props.product.purchase_blocked) return false
  if (props.product.variants.length > 0) {
    if (!selectedVariant.value) return false
    return selectedVariant.value.in_stock || !!props.product.backorder_available
  }
  return props.product.in_stock || !!props.product.backorder_available
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

const questionSortOptions = computed(() => [
  { value: 'newest', label: t('commerce.product.sortNewest') },
  { value: 'helpful', label: t('commerce.product.sortHelpful') },
])

const reviewSortOptions = computed(() => [
  { value: 'newest', label: t('commerce.product.sortNewest') },
  { value: 'helpful', label: t('commerce.product.sortHelpful') },
  { value: 'rating', label: t('commerce.product.sortRating') },
])

const reviewRatingFilterOptions = computed(() => [
  { value: '', label: t('commerce.product.allStars') },
  ...Array.from({ length: 5 }, (_, i) => ({ value: String(i + 1), label: t('commerce.product.starLabel', { n: i + 1 }) })),
])

const reviewRatingFormOptions = computed(() => Array.from({ length: 5 }, (_, i) => ({
  value: String(i + 1),
  label: t('commerce.product.starLabel', { n: i + 1 }),
})))

const purchaseSectionRef = ref<HTMLElement | null>(null)
const showStickyBar = ref(false)
let purchaseObserver: IntersectionObserver | null = null

onMounted(() => {
  const el = purchaseSectionRef.value
  if (!el) return
  purchaseObserver = new IntersectionObserver(
    ([entry]) => { showStickyBar.value = !entry?.isIntersecting },
    { threshold: 0 }
  )
  purchaseObserver.observe(el)
})

onUnmounted(() => {
  purchaseObserver?.disconnect()
})

const showStickyActions = computed(() =>
  showStickyBar.value && (canPurchase.value || props.loggedIn || !!props.compareUrl)
)

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

async function deleteReview() {
  const ok = await confirm({
    title: t('commerce.product.deleteReview'),
    message: t('commerce.product.deleteReviewConfirm'),
    confirmLabel: t('common.confirm'),
    variant: 'destructive',
  })
  if (!props.deleteReviewUrl || !ok) return
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
  <Head v-if="product.seo_title">
    <title>{{ product.seo_title }}</title>
    <meta v-if="product.seo_description" head-key="description" name="description" :content="product.seo_description" />
    <meta head-key="og:title" property="og:title" :content="product.seo_title" />
    <meta v-if="product.seo_description" head-key="og:description" property="og:description" :content="product.seo_description" />
    <meta v-if="product.seo_image" head-key="og:image" property="og:image" :content="product.seo_image" />
    <meta head-key="og:type" property="og:type" content="product" />
  </Head>

  <div :class="{ 'pb-24': showStickyActions }">

  <Breadcrumb :items="[
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.store'), href: routes.store },
    { label: product.name, current: true },
  ]" />

  <PageHeader :title="product.name" :subtitle="product.description || undefined" />
  <div v-if="product.membership_type_label" class="mb-2 flex flex-wrap items-center gap-2">
    <Badge variant="outline">{{ t('commerce.product.membershipProduct') }}</Badge>
    <Badge variant="secondary">{{ product.membership_type_label }}</Badge>
  </div>
  <p v-if="product.prerequisite_message" class="mb-4 rounded-md border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900 dark:border-amber-900 dark:bg-amber-950/40 dark:text-amber-100">
    {{ product.prerequisite_message }}
  </p>
  <p v-else-if="product.purchase_blocked" class="mb-4 rounded-md border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900 dark:border-amber-900 dark:bg-amber-950/40 dark:text-amber-100">
    {{ t('commerce.product.prerequisiteRequired') }}
  </p>
  <div v-if="product.purchased" class="mb-4 flex flex-wrap items-center gap-2">
    <Badge variant="default">{{ t('commerce.product.purchased') }}</Badge>
    <Button v-if="reorderUrl" type="button" size="sm" variant="outline" @click="router.post(reorderUrl)">{{ t('commerce.product.buyAgain') }}</Button>
  </div>

  <p v-if="askFromOrder" class="mb-4 rounded-md border border-blue-200 bg-blue-50 px-4 py-3 text-sm text-blue-900 dark:border-blue-900 dark:bg-blue-950/40 dark:text-blue-100">
    {{ t('commerce.product.askFromOrder', { order: askFromOrder.order_number, item: askFromOrder.item_name }) }}
  </p>

  <div class="mt-6 grid gap-8 lg:grid-cols-2 xl:grid-cols-5 lg:items-start">
    <div class="space-y-6 xl:col-span-3">
  <div v-if="allImages.length">
    <img
      v-if="activeGalleryImage"
      :src="activeGalleryImage"
      :alt="product.name"
      class="mb-3 max-h-[28rem] w-full rounded-lg border object-cover"
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

  <section v-if="product.version || product.changelog" class="rounded-lg border p-4">
    <h2 class="mb-2 text-sm font-semibold">{{ t('commerce.product.versionInfo') }}</h2>
    <p v-if="product.version" class="text-sm">{{ t('commerce.product.currentVersion', { version: product.version }) }}</p>
    <p v-if="product.changelog" class="mt-2 whitespace-pre-wrap text-sm text-muted-foreground">{{ product.changelog }}</p>
  </section>

  <section v-if="product.discussion_url || createDiscussionUrl" class="rounded-lg border p-4">
    <h2 class="mb-2 text-sm font-semibold">{{ t('commerce.product.discussion') }}</h2>
    <p v-if="product.discussion_replies_count !== null && product.discussion_replies_count !== undefined" class="text-sm text-muted-foreground">
      {{ t('commerce.product.discussionReplies', { count: product.discussion_replies_count }) }}
    </p>
    <div class="mt-2 flex gap-2">
      <Button v-if="product.discussion_url" as-child size="sm">
        <Link :href="product.discussion_url">{{ t('commerce.product.joinDiscussion') }}</Link>
      </Button>
      <Button v-else-if="createDiscussionUrl" type="button" size="sm" variant="outline" @click="createDiscussion">
        {{ t('commerce.product.startDiscussion') }}
      </Button>
    </div>
  </section>
    </div>

    <div class="space-y-6 xl:col-span-2 lg:sticky lg:top-20">
  <div ref="purchaseSectionRef">
  <Card>
    <CardContent class="space-y-3 pt-6">
      <div v-if="product.average_rating" class="text-sm">
        <span class="text-amber-500">★</span> {{ t('commerce.product.reviewsSummary', { rating: product.average_rating, count: reviewsCount ?? product.reviews.length }) }}
      </div>
      <div v-if="product.view_count" class="text-sm text-muted-foreground">
        {{ t('commerce.product.views', { count: product.view_count }) }}
      </div>

      <div v-if="product.variants.length" class="space-y-2">
        <Label>{{ t('commerce.product.variant') }}</Label>
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
              {{ !variant.in_stock ? t('commerce.product.outOfStock') : variant.low_stock ? t('commerce.product.lowStock') : t('commerce.product.inStock') }}
            </span>
          </button>
        </div>
      </div>

      <div class="flex justify-between text-sm">
        <span class="text-muted-foreground">{{ t('commerce.product.price') }}</span>
        <span class="font-medium">
          {{ displayPrice }}
          <span v-if="product.on_sale && product.compare_at_label" class="ml-2 text-xs font-normal text-muted-foreground line-through">{{ product.compare_at_label }}</span>
          <Badge v-if="product.on_sale" variant="default" class="ml-2 text-[10px]">{{ t('commerce.product.onSale') }}</Badge>
          <Badge v-if="product.discount_label" variant="outline" class="ml-1 text-[10px]">{{ product.discount_label }}</Badge>
        </span>
      </div>
      <div class="flex justify-between text-sm">
        <span class="text-muted-foreground">{{ t('commerce.product.type') }}</span>
        <span>{{ productTypeLabel }}</span>
      </div>
      <div class="flex justify-between text-sm">
        <span class="text-muted-foreground">{{ t('commerce.product.category') }}</span>
        <span>{{ product.category_name || '—' }}</span>
      </div>
      <div class="flex justify-between text-sm">
        <span class="text-muted-foreground">{{ t('commerce.product.stock') }}</span>
        <span :class="showLowStock && !product.purchase_blocked ? 'text-amber-600' : ''">
          {{ stockStatusLabel }}
        </span>
      </div>
      <div v-if="selectedVariant?.sku" class="flex justify-between text-sm">
        <span class="text-muted-foreground">SKU</span>
        <code class="text-xs">{{ selectedVariant.sku }}</code>
      </div>
      <div v-if="product.minimum_quantity && product.minimum_quantity > 1" class="flex justify-between text-sm">
        <span class="text-muted-foreground">{{ t('commerce.product.minQty') }}</span>
        <span>{{ t('commerce.product.minQtyValue', { n: product.minimum_quantity }) }}</span>
      </div>
      <div v-if="product.maximum_quantity" class="flex justify-between text-sm">
        <span class="text-muted-foreground">{{ t('commerce.product.maxQty') }}</span>
        <span>{{ t('commerce.product.maxQtyValue', { n: product.maximum_quantity }) }}</span>
      </div>
      <div v-if="product.purchase_limit" class="flex justify-between text-sm">
        <span class="text-muted-foreground">{{ t('commerce.product.purchaseLimit') }}</span>
        <span>{{ t('commerce.product.purchaseLimitValue', { n: product.purchase_limit }) }}</span>
      </div>
      <div v-if="canPurchase" class="space-y-2">
        <Label for="quantity">{{ t('commerce.product.quantity') }}</Label>
        <Input
          id="quantity"
          v-model.number="quantity"
          type="number"
          :min="product.minimum_quantity && product.minimum_quantity > 1 ? product.minimum_quantity : 1"
          :max="product.maximum_quantity || product.purchase_limit || 99"
          class="w-24"
        />
      </div>
    </CardContent>
  </Card>

  <div class="flex flex-wrap gap-3">
    <Button
      v-if="canPurchase"
      type="button"
      :disabled="product.variants.length > 0 && !selectedVariantId"
      @click="addToCart"
    >
      {{ t('commerce.product.addToCart') }}
    </Button>
    <Button v-if="loggedIn" type="button" variant="outline" @click="toggleWishlist">
      {{ wishlistedForSelection ? t('commerce.product.removeWishlist') : t('commerce.product.addWishlist') }}
    </Button>
    <Button
      v-if="loggedIn && priceAlertUrl"
      type="button"
      variant="outline"
      @click="togglePriceAlert"
    >
      {{ hasPriceAlert ? t('commerce.product.priceAlertOn') : t('commerce.product.priceAlert') }}
    </Button>
    <Button v-if="compareUrl" type="button" variant="outline" @click="toggleCompare">
      {{ compared ? t('commerce.product.removeCompare') : t('commerce.product.addCompare') }}{{ compareCount ? ` (${compareCount})` : '' }}
    </Button>
    <Button
      v-if="loggedIn && !canPurchase && !stockAlertSubscribed"
      type="button"
      variant="outline"
      :disabled="product.variants.length > 0 && !selectedVariantId"
      @click="subscribeStockAlert"
    >
      {{ t('commerce.product.stockAlert') }}
    </Button>
    <p v-else-if="loggedIn && !canPurchase && stockAlertSubscribed" class="flex items-center gap-2 self-center text-sm text-muted-foreground">
      {{ t('commerce.product.stockAlertOn') }}
      <Button v-if="stockAlertUnsubscribeUrl" type="button" variant="outline" size="sm" @click="unsubscribeStockAlert">{{ t('commerce.product.unsubscribe') }}</Button>
    </p>
    <Button as-child variant="outline">
      <Link :href="routes.store">{{ t('commerce.product.backToStore') }}</Link>
    </Button>
  </div>
  </div>
    </div>
  </div>

  <section class="mt-10">
    <div class="mb-4 flex flex-wrap items-center justify-between gap-2">
      <h2 class="text-sm font-semibold">{{ t('commerce.product.qa') }}</h2>
      <div class="flex flex-wrap items-center gap-2">
        <Select
          v-if="questions.length"
          :model-value="questionSort || 'newest'"
          :options="questionSortOptions"
          size="sm"
          @update:model-value="changeQuestionSort"
        />
        <form class="flex gap-2" @submit.prevent="searchQuestions">
          <Input v-model="questionSearch" :placeholder="t('commerce.product.searchQa')" class="h-8 max-w-xs text-sm" />
          <Button type="submit" size="sm" variant="outline">{{ t('commerce.product.search') }}</Button>
        </form>
      </div>
    </div>
    <div v-if="questions.length" class="mb-6 space-y-4">
      <article v-for="q in questions" :key="q.id" class="rounded-lg border p-4">
        <p class="text-sm font-medium">
          {{ t('commerce.product.questionPrefix') }}{{ q.body }}
          <Badge v-if="q.from_order" class="ml-2 text-[10px]">{{ t('commerce.product.purchasedQuestion') }}</Badge>
        </p>
        <p class="mt-1 text-xs text-muted-foreground">{{ q.author }} · {{ q.created_at }}</p>
        <div v-if="q.answers.length" class="mt-3 space-y-2 border-l-2 pl-3">
          <div v-for="answer in q.answers" :key="answer.id" class="text-sm">
            <span v-if="answer.official" class="mr-1 rounded bg-primary/10 px-1 text-xs text-primary">{{ t('commerce.product.official') }}</span>
            <span class="font-medium">{{ answer.author }}{{ t('common.colon') }}</span>{{ answer.body }}
            <p class="text-xs text-muted-foreground">{{ answer.created_at }}</p>
            <div v-if="answer.helpful_url" class="mt-1">
              <Button
                type="button"
                size="sm"
                variant="outline"
                :class="answer.helpful ? 'border-primary text-primary' : ''"
                @click="toggleAnswerHelpful(answer.helpful_url!)"
              >
                {{ t('commerce.product.helpfulCount', { count: answer.helpful_count || 0 }) }}
              </Button>
            </div>
          </div>
        </div>
        <form v-if="loggedIn" class="mt-3 space-y-2" @submit.prevent="submitAnswer(q.id, q.answerUrl)">
          <Textarea v-model="answerForms[q.id]" rows="2" :placeholder="t('commerce.product.answerPlaceholder')" />
          <Button type="submit" size="sm" variant="outline">{{ t('commerce.product.answer') }}</Button>
        </form>
      </article>
    </div>
    <p v-else class="mb-4 text-sm text-muted-foreground">{{ t('commerce.product.noQa') }}</p>
    <form v-if="loggedIn" class="space-y-3" @submit.prevent="submitQuestion">
      <Label>{{ t('commerce.product.ask') }}</Label>
      <Textarea v-model="questionForm.question.body" rows="3" :placeholder="t('commerce.product.askPlaceholder')" />
      <Button type="submit" size="sm" :disabled="questionForm.processing">{{ t('commerce.product.submitQuestion') }}</Button>
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
    <h2 class="mb-4 text-sm font-semibold">{{ t('commerce.product.relatedProducts') }}</h2>
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

  <section v-if="product.reviews.length || userReview || ratingBreakdown?.length" class="mt-10">
    <div class="mb-4 flex flex-wrap items-center justify-between gap-2">
      <h2 class="text-sm font-semibold">{{ t('commerce.product.userReviews') }}</h2>
      <Select
        v-if="product.reviews.length || reviewsCount"
        :model-value="reviewSort"
        :options="reviewSortOptions"
        size="sm"
        @update:model-value="changeReviewSort"
      />
      <Select
        :model-value="reviewRating === '' ? '' : String(reviewRating)"
        :options="reviewRatingFilterOptions"
        size="sm"
        @update:model-value="changeReviewRating"
      />
    </div>
    <div v-if="ratingBreakdown?.length" class="mb-4 space-y-1">
      <button
        v-for="entry in [...ratingBreakdown].sort((a, b) => b.rating - a.rating)"
        :key="entry.rating"
        type="button"
        class="flex w-full items-center gap-2 text-xs hover:opacity-80"
        @click="filterByRating(entry.rating)"
      >
        <span class="w-8">{{ t('commerce.product.starLabel', { n: entry.rating }) }}</span>
        <div class="h-2 flex-1 overflow-hidden rounded bg-muted">
          <div class="h-full bg-amber-400" :style="{ width: `${(entry.count / ratingBreakdownMax) * 100}%` }" />
        </div>
        <span class="w-8 text-muted-foreground">{{ entry.count }}</span>
      </button>
    </div>
    <div v-if="userReview && !editingReview" class="mb-4 rounded-lg border border-primary/30 bg-primary/5 p-4">
      <div class="mb-2 flex items-center justify-between">
        <p class="text-sm font-medium">{{ t('commerce.product.yourReview') }}</p>
        <div class="flex gap-2">
          <Button v-if="userReview.can_share_to_forum && userReview.share_to_forum_url" type="button" size="sm" variant="outline" @click="shareReviewToForum(userReview.share_to_forum_url!)">{{ t('commerce.product.shareToForum') }}</Button>
          <Button v-if="userReview.forum_post_url" as-child size="sm" variant="outline">
            <Link :href="userReview.forum_post_url">{{ t('commerce.product.viewForumPost') }}</Link>
          </Button>
          <Button v-if="canEditReview" type="button" size="sm" variant="outline" @click="startEditReview">{{ t('commerce.product.edit') }}</Button>
          <Button v-if="canDeleteReview" type="button" size="sm" variant="destructive" @click="deleteReview">{{ t('commerce.product.deleteReview') }}</Button>
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
            <Badge v-if="review.verified_purchaser" variant="default" class="ml-2 text-[10px]">{{ t('commerce.product.verifiedPurchaser') }}</Badge>
          </span>
          <span class="text-amber-500">{{ '★'.repeat(review.rating) }}</span>
        </div>
        <p v-if="review.body" class="text-sm">{{ review.body }}</p>
        <div v-if="review.merchant_reply" class="mt-3 rounded-md border border-emerald-200 bg-emerald-50/50 p-3 text-sm">
          <p class="text-xs font-medium text-emerald-800">{{ t('commerce.product.merchantReply') }}<span v-if="review.merchant_replied_at" class="ml-2 font-normal text-muted-foreground">{{ review.merchant_replied_at }}</span></p>
          <p class="mt-1">{{ review.merchant_reply }}</p>
        </div>
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
              {{ t('commerce.product.helpfulCount', { count: review.helpful_count || 0 }) }}
            </Button>
            <Button v-if="review.report_url" as-child variant="ghost" size="sm">
              <Link :href="review.report_url">{{ t('commerce.product.report') }}</Link>
            </Button>
          </div>
        </div>
      </article>
    </div>
    <Pagination v-if="reviewsPagination" :pagination="reviewsPagination" :base-path="routes.storeProduct(product.id)" page-param="review_page" />
    <Button
      v-if="reviewsPagination && reviewsPagination.page < reviewsPagination.pages"
      type="button"
      variant="outline"
      class="mt-3"
      @click="loadMoreReviews"
    >
      {{ t('commerce.product.loadMoreReviews') }}
    </Button>
  </section>

  <section v-if="loggedIn && (canReview || (canEditReview && editingReview))" class="mt-8">
    <h2 class="mb-3 text-sm font-semibold">{{ canEditReview ? t('commerce.product.editReview') : t('commerce.product.writeReview') }}</h2>
    <form class="space-y-3" @submit.prevent="submitReview">
      <div class="space-y-2">
        <Label>{{ t('commerce.product.rating') }}</Label>
        <Select
          :model-value="String(reviewForm.review.rating)"
          :options="reviewRatingFormOptions"
          size="sm"
          @update:model-value="(v) => { reviewForm.review.rating = Number(v) }"
        />
      </div>
      <Textarea v-model="reviewForm.review.body" rows="4" :placeholder="t('commerce.product.reviewBodyPlaceholder')" />
      <div v-if="existingReviewPhotos.length" class="space-y-2">
        <Label>{{ t('commerce.product.currentPhotos') }}</Label>
        <div class="flex flex-wrap gap-2">
          <a v-for="(url, i) in existingReviewPhotos" :key="i" :href="url" target="_blank" rel="noopener">
            <img :src="url" alt="" class="h-20 w-20 rounded object-cover ring-1 ring-border" />
          </a>
        </div>
      </div>
      <div class="space-y-2">
        <Label for="review_photos">{{ t('commerce.product.reviewPhotos') }}</Label>
        <FileInput
          accept="image/*"
          multiple
          :button-label="t('commerce.product.selectPhotos')"
          @change="onReviewPhotosChange"
        />
        <p v-if="reviewForm.review.photos.length" class="text-xs text-muted-foreground">
          {{ t('commerce.product.photosSelected', { n: reviewForm.review.photos.length }) }}
        </p>
      </div>
      <Button type="submit" :disabled="reviewForm.processing">{{ t('commerce.product.submitReview') }}</Button>
    </form>
  </section>

  </div>

  <div
    v-if="showStickyActions"
    class="fixed bottom-0 inset-x-0 z-30 border-t bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/80"
  >
    <div class="mx-auto flex max-w-5xl items-center justify-between gap-3 px-4 py-3">
      <div class="min-w-0">
        <p class="truncate text-sm font-medium">{{ product.name }}</p>
        <p class="text-sm text-primary">{{ displayPrice }}</p>
      </div>
      <div class="flex shrink-0 flex-wrap gap-2">
        <Button
          v-if="canPurchase"
          type="button"
          size="sm"
          :disabled="product.variants.length > 0 && !selectedVariantId"
          @click="addToCart"
        >
          {{ t('commerce.product.addToCart') }}
        </Button>
        <Button v-if="loggedIn" type="button" size="sm" variant="outline" @click="toggleWishlist">
          {{ wishlistedForSelection ? t('commerce.product.wishlistShort') : t('commerce.product.favorite') }}
        </Button>
        <Button v-if="compareUrl" type="button" size="sm" variant="outline" @click="toggleCompare">
          {{ compared ? t('commerce.product.comparing') : t('commerce.product.compareShort') }}
        </Button>
      </div>
    </div>
  </div>
</template>
