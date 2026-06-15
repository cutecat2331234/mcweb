<script setup lang="ts">
import { router } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Badge from '@/components/ui/Badge.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

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
  loggedIn?: boolean
}>()

function subscribe() {
  if (!props.availabilityAlertUrl) return
  router.post(props.availabilityAlertUrl, {}, { preserveScroll: true })
}

function unsubscribe() {
  if (!props.availabilityAlertUnsubscribeUrl) return
  router.delete(props.availabilityAlertUnsubscribeUrl, { preserveScroll: true })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '商城', href: routes.store },
    { label: product.name, current: true },
  ]" />

  <div class="mb-4 flex flex-wrap items-center gap-2">
    <Badge variant="outline">即将上架</Badge>
    <Badge v-if="product.available_at_label">{{ product.available_at_label }}</Badge>
  </div>

  <PageHeader :title="product.name" :subtitle="product.coming_soon_label || '商品尚未开售，可先订阅上架通知'" />

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

      <div v-if="loggedIn && availabilityAlertUrl" class="flex flex-wrap gap-2 pt-2">
        <Button v-if="!hasAvailabilityAlert" type="button" @click="subscribe">订阅上架通知</Button>
        <Button v-else type="button" variant="outline" @click="unsubscribe">已订阅 · 取消</Button>
      </div>
      <p v-else-if="!loggedIn" class="text-sm text-muted-foreground">
        <a :href="routes.signIn" class="text-primary hover:underline">登录</a> 后可订阅上架通知
      </p>
    </div>
  </div>
</template>
