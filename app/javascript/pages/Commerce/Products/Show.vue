<script setup lang="ts">
import { computed, ref, onMounted, onUnmounted, watch } from 'vue'
import { Head, Link, router, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import {
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuRoot,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from 'reka-ui'
import { MoreHorizontal } from '@lucide/vue'
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
import { commitNavigationEffect } from '@/lib/navigationReceipt'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

const menuItemClass = [
  'relative flex cursor-pointer select-none items-center rounded-sm px-2 py-1.5 text-sm outline-none',
  'data-[highlighted]:bg-accent data-[highlighted]:text-accent-foreground',
].join(' ')

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
  lock_version: number
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
  photos?: Array<{ id: number; url: string }>
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
  updateReviewUrl?: string | null
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
    lock_version: number
    body: string
    author: string
    created_at: string
    edited_at?: string | null
    answerUrl: string
    updateUrl?: string | null
    deleteUrl?: string | null
    answers: Array<{
      id: number
      lock_version: number
      body: string
      author: string
      official: boolean
      created_at: string
      edited_at?: string | null
      helpful_count?: number
      helpful?: boolean
      helpful_url?: string | null
      update_url?: string | null
      delete_url?: string | null
    }>
    from_order?: boolean
  }>
  questionsPagination?: import('@/components/portal/Pagination.vue').PaginationMeta
  questionQuery?: string
  viewReceipt?: { url: string; token: string } | null
}>()

watch(
  () => props.viewReceipt,
  (receipt) => {
    void commitNavigationEffect(receipt?.url, { receiptToken: receipt?.token })
  },
  { immediate: true },
)

const questionForm = useForm({ question: { body: '' } })
const answerForms = ref<Record<number, string>>({})
const editingQuestionId = ref<number | null>(null)
const editingQuestionBody = ref('')
const editingQuestionVersion = ref<number | null>(null)
const editingAnswerId = ref<number | null>(null)
const editingAnswerBody = ref('')
const editingAnswerVersion = ref<number | null>(null)

const selectedVariantId = ref<number | null>(
  props.product.variants.length === 1 ? props.product.variants[0].id : (props.product.saved_variant_id ?? null)
)
const minimumQuantity = computed(() => Math.max(1, Number(props.product.minimum_quantity) || 1))
const maximumQuantity = computed(() => {
  const limits = [99, props.product.maximum_quantity, props.product.purchase_limit]
    .map((value) => Number(value))
    .filter((value) => Number.isInteger(value) && value > 0)
  return Math.min(...limits)
})
const quantity = ref(minimumQuantity.value)
const quantityError = computed(() => {
  if (!Number.isInteger(quantity.value)) return t('commerce.product.quantityInteger')
  if (quantity.value < minimumQuantity.value) {
    return t('commerce.product.quantityMinimum', { n: minimumQuantity.value })
  }
  if (quantity.value > maximumQuantity.value) {
    return t('commerce.product.quantityMaximum', { n: maximumQuantity.value })
  }
  return ''
})
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
  review: {
    rating: number
    body: string
    photos: File[]
    retained_photo_ids: number[]
    photo_selection_present: boolean
    expected_version: number | null
  }
}>({
  review: {
    rating: 5,
    body: '',
    photos: [],
    retained_photo_ids: [],
    photo_selection_present: false,
    expected_version: null,
  },
})
const editingReview = ref(false)
const existingReviewPhotos = ref<Array<{ id: number; url: string }>>([])

function onReviewPhotosChange(files: File | File[]) {
  const list = Array.isArray(files) ? files : [files]
  reviewForm.review.photos = list.slice(0, Math.max(0, 3 - existingReviewPhotos.value.length))
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
  if (quantityError.value) return

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
  existingReviewPhotos.value = props.userReview.photos || []
  reviewForm.review.retained_photo_ids = existingReviewPhotos.value.map((photo) => photo.id)
  reviewForm.review.photo_selection_present = true
  reviewForm.review.expected_version = props.userReview.lock_version
  editingReview.value = true
}

function removeExistingReviewPhoto(id: number) {
  existingReviewPhotos.value = existingReviewPhotos.value.filter((photo) => photo.id !== id)
  reviewForm.review.retained_photo_ids = existingReviewPhotos.value.map((photo) => photo.id)
}

function cancelEditReview() {
  reviewForm.review.rating = 5
  reviewForm.review.body = ''
  reviewForm.review.photos = []
  reviewForm.review.retained_photo_ids = []
  reviewForm.review.photo_selection_present = false
  reviewForm.review.expected_version = null
  reviewForm.clearErrors()
  existingReviewPhotos.value = []
  editingReview.value = false
}

async function deleteReview() {
  const ok = await confirm({
    title: t('commerce.product.deleteReview'),
    message: props.userReview?.forum_post_url
      ? t('commerce.product.deleteReviewForumSnapshotConfirm')
      : t('commerce.product.deleteReviewConfirm'),
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
  const options = {
    preserveScroll: true,
    forceFormData: true,
    onSuccess: (page: { props: Record<string, unknown> }) => {
      if (responseHasAlert(page)) return
      cancelEditReview()
    },
  }
  if (editingReview.value && props.updateReviewUrl) {
    reviewForm.patch(props.updateReviewUrl, options)
  } else {
    reviewForm.post(props.reviewUrl, options)
  }
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

function startEditQuestion(question: { id: number; body: string; lock_version: number }) {
  editingQuestionId.value = question.id
  editingQuestionBody.value = question.body
  editingQuestionVersion.value = question.lock_version
}

function saveQuestion(url: string) {
  if (!editingQuestionBody.value.trim() || editingQuestionVersion.value === null) return
  router.patch(url, {
    question: {
      body: editingQuestionBody.value,
      expected_version: editingQuestionVersion.value,
    },
  }, {
    preserveScroll: true,
    onSuccess: (page) => {
      if (responseHasAlert(page)) return
      editingQuestionId.value = null
      editingQuestionBody.value = ''
      editingQuestionVersion.value = null
    },
  })
}

async function deleteQuestion(url: string) {
  const ok = await confirm({
    title: t('commerce.product.deleteQuestion'),
    message: t('commerce.product.deleteQuestionConfirm'),
    confirmLabel: t('common.confirm'),
    variant: 'destructive',
  })
  if (ok) router.delete(url, { preserveScroll: true })
}

function startEditAnswer(answer: { id: number; body: string; lock_version: number }) {
  editingAnswerId.value = answer.id
  editingAnswerBody.value = answer.body
  editingAnswerVersion.value = answer.lock_version
}

function saveAnswer(url: string) {
  if (!editingAnswerBody.value.trim() || editingAnswerVersion.value === null) return
  router.patch(url, {
    answer: {
      body: editingAnswerBody.value,
      expected_version: editingAnswerVersion.value,
    },
  }, {
    preserveScroll: true,
    onSuccess: (page) => {
      if (responseHasAlert(page)) return
      editingAnswerId.value = null
      editingAnswerBody.value = ''
      editingAnswerVersion.value = null
    },
  })
}

function responseHasAlert(page: { props: Record<string, unknown> }) {
  const flash = page.props.flash as { alert?: string | null } | undefined
  return Boolean(flash?.alert)
}

async function deleteAnswer(url: string) {
  const ok = await confirm({
    title: t('commerce.product.deleteAnswer'),
    message: t('commerce.product.deleteAnswerConfirm'),
    confirmLabel: t('common.confirm'),
    variant: 'destructive',
  })
  if (ok) router.delete(url, { preserveScroll: true })
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

  <div :class="{ 'pb-28 sm:pb-24': showStickyActions }">

  <Breadcrumb :items="[
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.store'), href: routes.store },
    { label: product.name, current: true },
  ]" />

  <PageHeader :title="product.name" :subtitle="product.description || undefined" />
  <div v-if="product.membership_type_label" class="mb-4 flex flex-wrap items-center gap-2">
    <Badge variant="outline">{{ t('commerce.product.membershipProduct') }}</Badge>
    <Badge variant="secondary">{{ product.membership_type_label }}</Badge>
  </div>
  <p v-if="product.prerequisite_message" class="mb-4 rounded-lg bg-amber-50 px-4 py-3 text-sm leading-relaxed text-amber-900 dark:bg-amber-950/40 dark:text-amber-100" role="status">
    {{ product.prerequisite_message }}
  </p>
  <p v-else-if="product.purchase_blocked" class="mb-4 rounded-lg bg-amber-50 px-4 py-3 text-sm leading-relaxed text-amber-900 dark:bg-amber-950/40 dark:text-amber-100" role="status">
    {{ t('commerce.product.prerequisiteRequired') }}
  </p>
  <div v-if="product.purchased" class="mb-4 flex flex-wrap items-center gap-2">
    <Badge variant="default">{{ t('commerce.product.purchased') }}</Badge>
    <Button v-if="reorderUrl" type="button" size="sm" variant="outline" @click="router.post(reorderUrl)">{{ t('commerce.product.buyAgain') }}</Button>
  </div>

  <p v-if="askFromOrder" class="mb-4 rounded-lg bg-blue-50 px-4 py-3 text-sm leading-relaxed text-blue-900 dark:bg-blue-950/40 dark:text-blue-100" role="status">
    {{ t('commerce.product.askFromOrder', { order: askFromOrder.order_number, item: askFromOrder.item_name }) }}
  </p>

  <div class="mt-8 grid gap-8 lg:grid-cols-2 lg:items-start xl:grid-cols-5">
    <div class="space-y-6 xl:col-span-3">
  <section v-if="allImages.length" :aria-label="t('commerce.product.gallery')">
    <img
      v-if="activeGalleryImage"
      :src="activeGalleryImage"
      :alt="product.name"
      class="mb-3 max-h-[32rem] w-full rounded-xl bg-muted/30 object-contain"
    />
    <div v-if="allImages.length > 1" class="flex gap-2 overflow-x-auto pb-2">
      <button
        v-for="(url, index) in allImages"
        :key="index"
        type="button"
        class="shrink-0 overflow-hidden rounded-md border transition-opacity focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
        :class="galleryIndex === index ? 'border-primary ring-2 ring-primary' : 'opacity-70 hover:opacity-100'"
        :aria-label="t('commerce.product.galleryImage', { n: index + 1 })"
        :aria-pressed="galleryIndex === index"
        @click="selectGalleryImage(index)"
      >
        <img :src="url" :alt="`${product.name} ${index + 1}`" class="h-16 w-16 object-cover" />
      </button>
    </div>
  </section>

  <section v-if="product.version || product.changelog" class="rounded-xl bg-muted/25 p-4 sm:p-5">
    <h2 class="mb-2 text-base font-semibold">{{ t('commerce.product.versionInfo') }}</h2>
    <p v-if="product.version" class="text-sm">{{ t('commerce.product.currentVersion', { version: product.version }) }}</p>
    <p v-if="product.changelog" class="mt-2 whitespace-pre-wrap text-sm text-muted-foreground">{{ product.changelog }}</p>
  </section>

  <section v-if="product.discussion_url || createDiscussionUrl" class="rounded-xl bg-muted/25 p-4 sm:p-5">
    <h2 class="mb-2 text-base font-semibold">{{ t('commerce.product.discussion') }}</h2>
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

    <div class="space-y-6 lg:sticky lg:top-20 xl:col-span-2">
      <div ref="purchaseSectionRef">
        <Card>
          <CardContent class="space-y-5 pt-6">
            <div aria-live="polite">
              <div class="flex flex-wrap items-baseline gap-x-2 gap-y-1">
                <p class="text-2xl font-semibold tracking-tight text-primary sm:text-3xl">
                  <span class="sr-only">{{ t('commerce.product.price') }}{{ t('common.colon') }}</span>
                  {{ displayPrice }}
                </p>
                <span v-if="product.on_sale && product.compare_at_label" class="text-sm text-muted-foreground line-through">{{ product.compare_at_label }}</span>
                <Badge v-if="product.on_sale" variant="default">{{ t('commerce.product.onSale') }}</Badge>
                <Badge v-if="product.discount_label" variant="outline">{{ product.discount_label }}</Badge>
              </div>
              <div class="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-sm text-muted-foreground">
                <span v-if="product.average_rating">
                  <span class="text-amber-500" aria-hidden="true">★</span>
                  {{ t('commerce.product.reviewsSummary', { rating: product.average_rating, count: reviewsCount ?? product.reviews.length }) }}
                </span>
                <span v-if="product.view_count">{{ t('commerce.product.views', { count: product.view_count }) }}</span>
              </div>
            </div>

            <fieldset v-if="product.variants.length" class="space-y-2">
              <legend class="text-sm font-medium">{{ t('commerce.product.variant') }}</legend>
              <div class="grid gap-2 sm:grid-cols-2 lg:grid-cols-1 xl:grid-cols-2">
                <button
                  v-for="variant in product.variants"
                  :key="variant.id"
                  type="button"
                  class="min-h-11 rounded-lg border px-3 py-2 text-left text-sm transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
                  :class="selectedVariantId === variant.id ? 'border-primary bg-primary/10' : 'hover:bg-muted'"
                  :aria-pressed="selectedVariantId === variant.id"
                  @click="selectedVariantId = variant.id"
                >
                  <span class="block font-medium">{{ variant.name }} · {{ variant.price_label }}</span>
                  <span class="mt-0.5 block text-xs text-muted-foreground">
                    {{ !variant.in_stock ? t('commerce.product.outOfStock') : variant.low_stock ? t('commerce.product.lowStock') : t('commerce.product.inStock') }}
                  </span>
                </button>
              </div>
            </fieldset>

            <dl class="grid gap-2 rounded-lg bg-muted/30 p-3">
              <div class="grid grid-cols-[minmax(0,1fr)_minmax(0,1.5fr)] gap-3 text-sm">
                <dt class="text-muted-foreground">{{ t('commerce.product.type') }}</dt>
                <dd class="break-words text-right font-medium">{{ productTypeLabel }}</dd>
              </div>
              <div class="grid grid-cols-[minmax(0,1fr)_minmax(0,1.5fr)] gap-3 text-sm">
                <dt class="text-muted-foreground">{{ t('commerce.product.category') }}</dt>
                <dd class="break-words text-right">{{ product.category_name || '—' }}</dd>
              </div>
              <div class="grid grid-cols-[minmax(0,1fr)_minmax(0,1.5fr)] gap-3 text-sm">
                <dt class="text-muted-foreground">{{ t('commerce.product.stock') }}</dt>
                <dd class="text-right font-medium" :class="showLowStock && !product.purchase_blocked ? 'text-amber-700 dark:text-amber-300' : ''">
                  {{ stockStatusLabel }}
                </dd>
              </div>
              <div v-if="selectedVariant?.sku" class="grid grid-cols-[minmax(0,1fr)_minmax(0,1.5fr)] gap-3 text-sm">
                <dt class="text-muted-foreground">SKU</dt>
                <dd class="min-w-0 break-all text-right"><code class="text-xs">{{ selectedVariant.sku }}</code></dd>
              </div>
              <div v-if="product.minimum_quantity && product.minimum_quantity > 1" class="grid grid-cols-[minmax(0,1fr)_minmax(0,1.5fr)] gap-3 text-sm">
                <dt class="text-muted-foreground">{{ t('commerce.product.minQty') }}</dt>
                <dd class="text-right">{{ t('commerce.product.minQtyValue', { n: product.minimum_quantity }) }}</dd>
              </div>
              <div v-if="product.maximum_quantity" class="grid grid-cols-[minmax(0,1fr)_minmax(0,1.5fr)] gap-3 text-sm">
                <dt class="text-muted-foreground">{{ t('commerce.product.maxQty') }}</dt>
                <dd class="text-right">{{ t('commerce.product.maxQtyValue', { n: product.maximum_quantity }) }}</dd>
              </div>
              <div v-if="product.purchase_limit" class="grid grid-cols-[minmax(0,1fr)_minmax(0,1.5fr)] gap-3 text-sm">
                <dt class="text-muted-foreground">{{ t('commerce.product.purchaseLimit') }}</dt>
                <dd class="text-right">{{ t('commerce.product.purchaseLimitValue', { n: product.purchase_limit }) }}</dd>
              </div>
            </dl>

            <div v-if="canPurchase" class="space-y-2">
              <Label for="quantity">{{ t('commerce.product.quantity') }}</Label>
              <Input
                id="quantity"
                v-model.number="quantity"
                type="number"
                :min="minimumQuantity"
                :max="maximumQuantity"
                step="1"
                :aria-invalid="!!quantityError"
                :aria-describedby="quantityError ? 'product-quantity-error' : undefined"
                class="w-full sm:max-w-32"
              />
              <p v-if="quantityError" id="product-quantity-error" class="text-xs text-destructive" role="alert">
                {{ quantityError }}
              </p>
            </div>

            <Button
              v-if="canPurchase"
              type="button"
              class="w-full"
              :disabled="(product.variants.length > 0 && !selectedVariantId) || !!quantityError"
              @click="addToCart"
            >
              {{ t('commerce.product.addToCart') }}
            </Button>
            <Button
              v-if="loggedIn && !canPurchase && !stockAlertSubscribed"
              type="button"
              variant="outline"
              class="w-full"
              :disabled="product.variants.length > 0 && !selectedVariantId"
              @click="subscribeStockAlert"
            >
              {{ t('commerce.product.stockAlert') }}
            </Button>
            <div
              v-else-if="loggedIn && !canPurchase && stockAlertSubscribed"
              class="flex flex-wrap items-center justify-between gap-2 rounded-lg bg-muted/30 px-3 py-2 text-sm text-muted-foreground"
              role="status"
            >
              <span>{{ t('commerce.product.stockAlertOn') }}</span>
              <Button v-if="stockAlertUnsubscribeUrl" type="button" variant="ghost" size="sm" @click="unsubscribeStockAlert">{{ t('commerce.product.unsubscribe') }}</Button>
            </div>

            <div class="grid gap-2" :class="loggedIn ? 'grid-cols-2' : 'grid-cols-1'">
              <Button v-if="loggedIn" type="button" variant="outline" class="min-w-0" @click="toggleWishlist">
                <span class="truncate">{{ wishlistedForSelection ? t('commerce.product.removeWishlist') : t('commerce.product.addWishlist') }}</span>
              </Button>
              <DropdownMenuRoot :modal="false">
                <DropdownMenuTrigger as-child>
                  <Button type="button" variant="outline" class="w-full min-w-0">
                    <MoreHorizontal class="h-4 w-4 shrink-0" aria-hidden="true" />
                    <span class="truncate">{{ t('commerce.product.moreActions') }}</span>
                  </Button>
                </DropdownMenuTrigger>
                <DropdownMenuContent
                  class="z-50 max-h-[70vh] min-w-[13rem] overflow-y-auto rounded-md border bg-popover p-1 text-popover-foreground shadow-md"
                  :side-offset="6"
                  align="end"
                >
                  <DropdownMenuLabel class="px-2 py-1.5 text-xs text-muted-foreground">
                    {{ t('commerce.product.purchaseActions') }}
                  </DropdownMenuLabel>
                  <DropdownMenuItem
                    v-if="loggedIn && priceAlertUrl"
                    :class="menuItemClass"
                    @select="togglePriceAlert"
                  >
                    {{ hasPriceAlert ? t('commerce.product.priceAlertOn') : t('commerce.product.priceAlert') }}
                  </DropdownMenuItem>
                  <DropdownMenuItem v-if="compareUrl" :class="menuItemClass" @select="toggleCompare">
                    {{ compared ? t('commerce.product.removeCompare') : t('commerce.product.addCompare') }}{{ compareCount ? ` (${compareCount})` : '' }}
                  </DropdownMenuItem>
                  <DropdownMenuSeparator v-if="(loggedIn && priceAlertUrl) || compareUrl" class="my-1 h-px bg-border" />
                  <DropdownMenuItem as-child>
                    <Link :href="routes.store" :class="menuItemClass">{{ t('commerce.product.backToStore') }}</Link>
                  </DropdownMenuItem>
                </DropdownMenuContent>
              </DropdownMenuRoot>
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  </div>

  <section class="mt-12">
    <div class="mb-5 flex flex-col items-start gap-3 sm:flex-row sm:items-center sm:justify-between">
      <h2 class="text-lg font-semibold tracking-tight">{{ t('commerce.product.qa') }}</h2>
      <div
        class="grid w-full gap-2 sm:w-auto"
        :class="questions.length ? 'sm:grid-cols-[minmax(8rem,auto)_minmax(14rem,1fr)]' : 'sm:min-w-80'"
      >
        <label v-if="questions.length" for="question-sort" class="sr-only">{{ t('commerce.product.sortQuestions') }}</label>
        <Select
          v-if="questions.length"
          id="question-sort"
          :model-value="questionSort || 'newest'"
          :options="questionSortOptions"
          size="sm"
          block
          @update:model-value="changeQuestionSort"
        />
        <form role="search" class="grid min-w-0 grid-cols-[minmax(0,1fr)_auto] gap-2" @submit.prevent="searchQuestions">
          <label for="question-search" class="sr-only">{{ t('commerce.product.searchQa') }}</label>
          <Input id="question-search" v-model="questionSearch" :placeholder="t('commerce.product.searchQa')" class="h-8 min-w-0 text-sm" />
          <Button type="submit" size="sm" variant="outline">{{ t('commerce.product.search') }}</Button>
        </form>
      </div>
    </div>
    <div v-if="questions.length" class="mb-6 space-y-4">
      <article v-for="q in questions" :key="q.id" class="rounded-xl bg-muted/25 p-4 sm:p-5">
        <div v-if="editingQuestionId === q.id" class="space-y-2">
          <Label :for="`edit-question-${q.id}`">{{ t('commerce.product.editQuestion') }}</Label>
          <Textarea :id="`edit-question-${q.id}`" v-model="editingQuestionBody" rows="3" maxlength="2000" />
          <div class="flex flex-wrap gap-2">
            <Button type="button" size="sm" @click="saveQuestion(q.updateUrl!)">{{ t('common.save') }}</Button>
            <Button type="button" size="sm" variant="outline" @click="editingQuestionId = null">{{ t('common.cancel') }}</Button>
          </div>
        </div>
        <template v-else>
          <div class="flex flex-wrap items-start justify-between gap-2">
            <p class="min-w-0 break-words text-sm font-medium leading-relaxed">
              {{ t('commerce.product.questionPrefix') }}{{ q.body }}
              <Badge v-if="q.from_order" class="ml-2 text-[10px]">{{ t('commerce.product.purchasedQuestion') }}</Badge>
            </p>
            <div v-if="q.updateUrl || q.deleteUrl" class="flex shrink-0 flex-wrap gap-2">
              <Button v-if="q.updateUrl" type="button" size="sm" variant="outline" @click="startEditQuestion(q)">{{ t('commerce.product.edit') }}</Button>
              <Button v-if="q.deleteUrl" type="button" size="sm" variant="destructive" @click="deleteQuestion(q.deleteUrl)">{{ t('common.delete') }}</Button>
            </div>
          </div>
          <p class="mt-1 text-xs text-muted-foreground">
            {{ q.author }} · {{ q.created_at }}
            <span v-if="q.edited_at"> · {{ t('commerce.product.editedAt', { time: q.edited_at }) }}</span>
          </p>
        </template>
        <div v-if="q.answers.length" class="mt-4 space-y-3 border-l-2 border-primary/20 pl-3 sm:pl-4">
          <div v-for="answer in q.answers" :key="answer.id" class="text-sm">
            <div v-if="editingAnswerId === answer.id" class="space-y-2">
              <Label :for="`edit-answer-${answer.id}`">{{ t('commerce.product.editAnswer') }}</Label>
              <Textarea :id="`edit-answer-${answer.id}`" v-model="editingAnswerBody" rows="3" maxlength="2000" />
              <div class="flex flex-wrap gap-2">
                <Button type="button" size="sm" @click="saveAnswer(answer.update_url!)">{{ t('common.save') }}</Button>
                <Button type="button" size="sm" variant="outline" @click="editingAnswerId = null">{{ t('common.cancel') }}</Button>
              </div>
            </div>
            <template v-else>
              <div class="flex flex-wrap items-start justify-between gap-2">
                <p class="min-w-0 break-words leading-relaxed">
                  <span v-if="answer.official" class="mr-1 rounded bg-primary/10 px-1.5 py-0.5 text-xs text-primary">{{ t('commerce.product.official') }}</span>
                  <span class="font-medium">{{ answer.author }}{{ t('common.colon') }}</span>
                  {{ answer.body }}
                </p>
                <div v-if="answer.update_url || answer.delete_url" class="flex shrink-0 flex-wrap gap-2">
                  <Button v-if="answer.update_url" type="button" size="sm" variant="outline" @click="startEditAnswer(answer)">{{ t('commerce.product.edit') }}</Button>
                  <Button v-if="answer.delete_url" type="button" size="sm" variant="destructive" @click="deleteAnswer(answer.delete_url)">{{ t('common.delete') }}</Button>
                </div>
              </div>
              <p class="mt-1 text-xs text-muted-foreground">
                {{ answer.created_at }}
                <span v-if="answer.edited_at"> · {{ t('commerce.product.editedAt', { time: answer.edited_at }) }}</span>
              </p>
            </template>
            <div v-if="answer.helpful_url && editingAnswerId !== answer.id" class="mt-1">
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
          <label :for="`answer-${q.id}`" class="sr-only">{{ t('commerce.product.answerPlaceholder') }}</label>
          <Textarea :id="`answer-${q.id}`" v-model="answerForms[q.id]" rows="2" maxlength="2000" :placeholder="t('commerce.product.answerPlaceholder')" />
          <Button type="submit" size="sm" variant="outline">{{ t('commerce.product.answer') }}</Button>
        </form>
      </article>
    </div>
    <p v-else class="mb-4 text-sm text-muted-foreground">{{ t('commerce.product.noQa') }}</p>
    <form v-if="loggedIn" class="max-w-2xl space-y-3 rounded-xl bg-muted/20 p-4 sm:p-5" :aria-busy="questionForm.processing" @submit.prevent="submitQuestion">
      <Label for="product-question">{{ t('commerce.product.ask') }}</Label>
      <Textarea id="product-question" v-model="questionForm.question.body" rows="3" maxlength="2000" :placeholder="t('commerce.product.askPlaceholder')" />
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

  <section v-if="related_products.length" class="mt-12">
    <h2 class="mb-5 text-lg font-semibold tracking-tight">{{ t('commerce.product.relatedProducts') }}</h2>
    <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
      <Link
        v-for="item in related_products"
        :key="item.id"
        :href="item.url"
        class="rounded-xl bg-muted/25 p-3 transition-colors hover:bg-muted/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
      >
        <img v-if="item.image_url" :src="item.image_url" :alt="item.name" class="mb-3 aspect-[4/3] w-full rounded-lg object-cover" />
        <p class="break-words text-sm font-medium">{{ item.name }}</p>
        <p class="mt-1 text-sm font-medium text-primary">{{ item.price_label }}</p>
      </Link>
    </div>
  </section>

  <section v-if="product.reviews.length || userReview || ratingBreakdown?.length" class="mt-12">
    <div class="mb-5 flex flex-col items-start gap-3 sm:flex-row sm:items-center sm:justify-between">
      <h2 class="text-lg font-semibold tracking-tight">{{ t('commerce.product.userReviews') }}</h2>
      <div
        class="grid w-full gap-2 sm:w-auto"
        :class="product.reviews.length || reviewsCount ? 'grid-cols-2' : 'grid-cols-1'"
      >
        <label v-if="product.reviews.length || reviewsCount" for="review-sort" class="sr-only">{{ t('commerce.product.sortReviews') }}</label>
        <Select
          v-if="product.reviews.length || reviewsCount"
          id="review-sort"
          :model-value="reviewSort"
          :options="reviewSortOptions"
          size="sm"
          block
          @update:model-value="changeReviewSort"
        />
        <label for="review-rating-filter" class="sr-only">{{ t('commerce.product.filterReviews') }}</label>
        <Select
          id="review-rating-filter"
          :model-value="reviewRating === '' ? '' : String(reviewRating)"
          :options="reviewRatingFilterOptions"
          size="sm"
          block
          @update:model-value="changeReviewRating"
        />
      </div>
    </div>
    <div v-if="ratingBreakdown?.length" class="mb-5 max-w-2xl space-y-1">
      <button
        v-for="entry in [...ratingBreakdown].sort((a, b) => b.rating - a.rating)"
        :key="entry.rating"
        type="button"
        class="flex w-full items-center gap-2 rounded-md px-2 py-1 text-xs hover:bg-muted/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
        :aria-pressed="reviewRating === entry.rating"
        @click="filterByRating(entry.rating)"
      >
        <span class="w-8">{{ t('commerce.product.starLabel', { n: entry.rating }) }}</span>
        <div
          class="h-2 flex-1 overflow-hidden rounded bg-muted"
          role="progressbar"
          :aria-label="t('commerce.product.ratingCount', { rating: entry.rating, count: entry.count })"
          :aria-valuenow="entry.count"
          aria-valuemin="0"
          :aria-valuemax="ratingBreakdownMax"
        >
          <div class="h-full bg-amber-400" :style="{ width: `${(entry.count / ratingBreakdownMax) * 100}%` }" />
        </div>
        <span class="w-8 text-muted-foreground">{{ entry.count }}</span>
      </button>
    </div>
    <div v-if="userReview && !editingReview" class="mb-5 rounded-xl bg-primary/5 p-4 sm:p-5">
      <div class="mb-3 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <p class="text-sm font-medium">{{ t('commerce.product.yourReview') }}</p>
        <div class="flex flex-wrap gap-2">
          <Button v-if="userReview.can_share_to_forum && userReview.share_to_forum_url" type="button" size="sm" variant="outline" @click="shareReviewToForum(userReview.share_to_forum_url!)">{{ t('commerce.product.shareToForum') }}</Button>
          <Button v-if="userReview.forum_post_url" as-child size="sm" variant="outline">
            <Link :href="userReview.forum_post_url">{{ t('commerce.product.viewForumPost') }}</Link>
          </Button>
          <Button v-if="canEditReview" type="button" size="sm" variant="outline" @click="startEditReview">{{ t('commerce.product.edit') }}</Button>
          <Button v-if="canDeleteReview" type="button" size="sm" variant="destructive" @click="deleteReview">{{ t('commerce.product.deleteReview') }}</Button>
        </div>
      </div>
      <div class="mb-2 flex flex-wrap items-center justify-between gap-2 text-sm">
        <span class="text-amber-500">{{ '★'.repeat(userReview.rating) }}</span>
        <span class="text-xs text-muted-foreground">{{ userReview.created_at }}</span>
      </div>
      <p v-if="userReview.body" class="break-words text-sm leading-relaxed">{{ userReview.body }}</p>
      <p v-if="userReview.forum_post_url" class="mt-3 rounded-md border bg-background px-3 py-2 text-xs text-muted-foreground">
        {{ t('commerce.product.forumSnapshotNotice') }}
      </p>
      <div v-if="userReview.photo_urls?.length" class="mt-2 flex flex-wrap gap-2">
        <img v-for="(url, i) in userReview.photo_urls" :key="i" :src="url" :alt="t('commerce.product.reviewPhoto', { n: i + 1 })" class="h-20 w-20 rounded object-cover" />
      </div>
    </div>
    <div class="space-y-3">
      <article v-for="review in product.reviews" :key="review.id" class="rounded-xl bg-muted/25 p-4 sm:p-5">
        <div class="mb-2 flex flex-wrap items-center justify-between gap-2 text-sm">
          <span class="break-words font-medium">
            {{ review.author }}
            <Badge v-if="review.verified_purchaser" variant="default" class="ml-2 text-[10px]">{{ t('commerce.product.verifiedPurchaser') }}</Badge>
          </span>
          <span class="text-amber-500">{{ '★'.repeat(review.rating) }}</span>
        </div>
        <p v-if="review.body" class="break-words text-sm leading-relaxed">{{ review.body }}</p>
        <div v-if="review.merchant_reply" class="mt-3 rounded-lg bg-emerald-50/70 p-3 text-sm dark:bg-emerald-950/20">
          <p class="flex flex-wrap gap-x-2 text-xs font-medium text-emerald-800 dark:text-emerald-200">
            <span>{{ t('commerce.product.merchantReply') }}</span>
            <span v-if="review.merchant_replied_at" class="font-normal text-muted-foreground">{{ review.merchant_replied_at }}</span>
          </p>
          <p class="mt-1 break-words leading-relaxed">{{ review.merchant_reply }}</p>
        </div>
        <div v-if="review.photo_urls?.length" class="mt-2 flex flex-wrap gap-2">
          <a v-for="(url, i) in review.photo_urls" :key="i" :href="url" target="_blank" rel="noopener" class="rounded focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
            <img :src="url" :alt="t('commerce.product.reviewPhotoBy', { author: review.author, n: i + 1 })" class="h-20 w-20 rounded object-cover ring-1 ring-border hover:opacity-90" />
          </a>
        </div>
        <div class="mt-3 flex flex-wrap items-center justify-between gap-2">
          <p class="text-xs text-muted-foreground">{{ review.created_at }}</p>
          <div class="flex flex-wrap gap-2">
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

  <section v-if="loggedIn && (canReview || (canEditReview && editingReview))" class="mt-10 max-w-2xl">
    <h2 class="mb-4 text-lg font-semibold tracking-tight">{{ canEditReview ? t('commerce.product.editReview') : t('commerce.product.writeReview') }}</h2>
    <form class="space-y-4 rounded-xl bg-muted/20 p-4 sm:p-5" :aria-busy="reviewForm.processing" @submit.prevent="submitReview">
      <p v-if="editingReview && userReview?.forum_post_url" class="rounded-md border bg-background px-3 py-2 text-xs text-muted-foreground">
        {{ t('commerce.product.forumSnapshotNotice') }}
      </p>
      <div class="space-y-2">
        <Label for="review-rating">{{ t('commerce.product.rating') }}</Label>
        <Select
          id="review-rating"
          :model-value="String(reviewForm.review.rating)"
          :options="reviewRatingFormOptions"
          size="sm"
          @update:model-value="(v) => { reviewForm.review.rating = Number(v) }"
        />
      </div>
      <div class="space-y-2">
        <Label for="review-body">{{ t('commerce.product.reviewBody') }}</Label>
        <Textarea id="review-body" v-model="reviewForm.review.body" rows="4" maxlength="5000" :placeholder="t('commerce.product.reviewBodyPlaceholder')" />
      </div>
      <div v-if="existingReviewPhotos.length" class="space-y-2">
        <Label>{{ t('commerce.product.currentPhotos') }}</Label>
        <div class="flex flex-wrap gap-2">
          <div v-for="(photo, i) in existingReviewPhotos" :key="photo.id" class="space-y-1">
            <a :href="photo.url" target="_blank" rel="noopener" class="block rounded focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
              <img :src="photo.url" :alt="t('commerce.product.reviewPhoto', { n: i + 1 })" class="h-20 w-20 rounded object-cover ring-1 ring-border" />
            </a>
            <Button type="button" size="sm" variant="outline" class="w-full" @click="removeExistingReviewPhoto(photo.id)">
              {{ t('commerce.product.removePhoto') }}
            </Button>
          </div>
        </div>
      </div>
      <div class="space-y-2">
        <p class="text-sm font-medium">{{ t('commerce.product.reviewPhotos') }}</p>
        <FileInput
          accept="image/jpeg,image/png,image/gif,image/webp"
          multiple
          :button-label="t('commerce.product.selectPhotos')"
          @change="onReviewPhotosChange"
        />
        <p v-if="reviewForm.review.photos.length" class="text-xs text-muted-foreground">
          {{ t('commerce.product.photosSelected', { n: reviewForm.review.photos.length }) }}
        </p>
      </div>
      <div class="flex flex-col gap-2 sm:flex-row">
        <Button type="submit" class="w-full sm:w-auto" :disabled="reviewForm.processing">
          {{ editingReview ? t('commerce.product.saveReview') : t('commerce.product.submitReview') }}
        </Button>
        <Button v-if="editingReview" type="button" class="w-full sm:w-auto" variant="outline" :disabled="reviewForm.processing" @click="cancelEditReview">
          {{ t('common.cancel') }}
        </Button>
      </div>
    </form>
  </section>

  </div>

  <div
    v-if="showStickyActions"
    class="fixed inset-x-0 bottom-0 z-30 border-t bg-background/95 shadow-[0_-4px_18px_rgba(0,0,0,0.06)] backdrop-blur supports-[backdrop-filter]:bg-background/80"
  >
    <div
      class="mx-auto flex max-w-5xl items-center justify-between gap-2 px-3 pt-3 sm:gap-3 sm:px-4"
      style="padding-bottom: max(0.75rem, env(safe-area-inset-bottom))"
    >
      <div class="min-w-0">
        <p class="truncate text-sm font-medium">{{ product.name }}</p>
        <p class="text-sm font-medium text-primary" aria-live="polite">{{ displayPrice }}</p>
      </div>
      <div class="flex shrink-0 items-center gap-2">
        <Button
          v-if="canPurchase"
          type="button"
          size="sm"
          :disabled="product.variants.length > 0 && !selectedVariantId"
          @click="addToCart"
        >
          {{ t('commerce.product.addToCart') }}
        </Button>
        <Button
          v-else-if="loggedIn && !stockAlertSubscribed"
          type="button"
          size="sm"
          variant="outline"
          :disabled="product.variants.length > 0 && !selectedVariantId"
          @click="subscribeStockAlert"
        >
          {{ t('commerce.product.stockAlert') }}
        </Button>
        <DropdownMenuRoot v-if="loggedIn || compareUrl" :modal="false">
          <DropdownMenuTrigger as-child>
            <Button
              type="button"
              size="sm"
              variant="outline"
              class="h-8 w-8 px-0"
              :aria-label="t('commerce.product.moreActions')"
              :title="t('commerce.product.moreActions')"
            >
              <MoreHorizontal class="h-4 w-4" aria-hidden="true" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent
            class="z-50 max-h-[70vh] min-w-[13rem] overflow-y-auto rounded-md border bg-popover p-1 text-popover-foreground shadow-md"
            :side-offset="6"
            align="end"
          >
            <DropdownMenuLabel class="px-2 py-1.5 text-xs text-muted-foreground">
              {{ t('commerce.product.purchaseActions') }}
            </DropdownMenuLabel>
            <DropdownMenuItem v-if="loggedIn" :class="menuItemClass" @select="toggleWishlist">
              {{ wishlistedForSelection ? t('commerce.product.removeWishlist') : t('commerce.product.addWishlist') }}
            </DropdownMenuItem>
            <DropdownMenuItem v-if="loggedIn && priceAlertUrl" :class="menuItemClass" @select="togglePriceAlert">
              {{ hasPriceAlert ? t('commerce.product.priceAlertOn') : t('commerce.product.priceAlert') }}
            </DropdownMenuItem>
            <DropdownMenuItem v-if="compareUrl" :class="menuItemClass" @select="toggleCompare">
              {{ compared ? t('commerce.product.removeCompare') : t('commerce.product.addCompare') }}{{ compareCount ? ` (${compareCount})` : '' }}
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenuRoot>
      </div>
    </div>
  </div>
</template>
