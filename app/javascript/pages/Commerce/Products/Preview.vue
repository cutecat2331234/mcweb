<script setup lang="ts">
import { router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Badge from '@/components/ui/Badge.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

const props = defineProps<{
  product: {
    id: string
    name: string
    slug: string
    description: string | null
    summary?: string | null
    price_label: string
    compare_at_label?: string | null
    on_sale?: boolean
    discount_label?: string | null
    category_name: string | null
    image_url: string | null
    gallery_urls: string[]
    available_at_label: string | null
    coming_soon_label?: string | null
  }
  hasAvailabilityAlert?: boolean
  availabilityAlertUrl?: string | null
  availabilityAlertUnsubscribeUrl?: string | null
  wishlistUrl?: string | null
  wishlisted?: boolean
  compareUrl?: string | null
  compared?: boolean
  compareCount?: number
  loggedIn?: boolean
}>()

function toggleWishlist() {
  if (!props.wishlistUrl) return
  router.post(props.wishlistUrl, {}, { preserveScroll: true })
}

function subscribe() {
  if (!props.availabilityAlertUrl) return
  router.post(props.availabilityAlertUrl, {}, { preserveScroll: true })
}

function unsubscribe() {
  if (!props.availabilityAlertUnsubscribeUrl) return
  router.delete(props.availabilityAlertUnsubscribeUrl, { preserveScroll: true })
}

function toggleCompare() {
  if (!props.compareUrl) return
  router.post(props.compareUrl, {}, { preserveScroll: true })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.store'), href: routes.store },
    { label: product.name, current: true },
  ]" />

  <div class="mb-4 flex flex-wrap items-center gap-2">
    <Badge variant="outline">{{ t('commerce.productPreview.comingSoon') }}</Badge>
    <Badge v-if="product.available_at_label">{{ product.available_at_label }}</Badge>
  </div>

  <PageHeader :title="product.name" :subtitle="product.coming_soon_label || t('commerce.productPreview.subtitle')" />

  <div class="grid gap-8 lg:grid-cols-2">
    <div>
      <img
        v-if="product.image_url"
        :src="product.image_url"
        :alt="product.name"
        class="w-full max-w-md rounded-lg border object-cover grayscale"
      />
      <div v-if="product.gallery_urls?.length > 1" class="mt-3 flex flex-wrap gap-2">
        <img
          v-for="(url, index) in product.gallery_urls"
          :key="index"
          :src="url"
          alt=""
          class="h-16 w-16 rounded border object-cover opacity-80"
        />
      </div>
    </div>
    <div class="space-y-4">
      <p v-if="product.category_name" class="text-sm text-muted-foreground">{{ product.category_name }}</p>
      <p class="text-2xl font-semibold">{{ product.price_label }}</p>
      <p v-if="product.compare_at_label" class="text-sm text-muted-foreground line-through">{{ product.compare_at_label }}</p>
      <p v-if="product.discount_label" class="text-sm text-rose-600">{{ product.discount_label }}</p>
      <p v-if="product.summary" class="text-sm text-muted-foreground">{{ product.summary }}</p>
      <div v-if="product.description" class="prose prose-sm max-w-none dark:prose-invert" v-html="product.description" />

      <div v-if="loggedIn" class="flex flex-wrap gap-2 pt-2">
        <Button v-if="wishlistUrl" type="button" :variant="wishlisted ? 'outline' : 'secondary'" @click="toggleWishlist">
          {{ wishlisted ? t('commerce.productPreview.inWishlist') : t('commerce.productPreview.addWishlist') }}
        </Button>
        <Button v-if="compareUrl" type="button" variant="outline" @click="toggleCompare">
          {{ compared ? t('commerce.productPreview.removeCompare') : t('commerce.productPreview.addCompare') }}{{ compareCount ? ` (${compareCount})` : '' }}
        </Button>
        <Button v-if="!hasAvailabilityAlert && availabilityAlertUrl" type="button" @click="subscribe">{{ t('commerce.productPreview.subscribeAvailability') }}</Button>
        <Button v-else-if="hasAvailabilityAlert && availabilityAlertUnsubscribeUrl" type="button" variant="outline" @click="unsubscribe">{{ t('commerce.productPreview.subscribedCancel') }}</Button>
      </div>
      <p v-else-if="!loggedIn" class="text-sm text-muted-foreground">
        <a :href="routes.signIn" class="text-primary hover:underline">{{ t('commerce.productPreview.signInToSubscribe') }}</a>{{ t('commerce.productPreview.signInHint') }}
      </p>
    </div>
  </div>
</template>
