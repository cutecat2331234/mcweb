<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

const props = defineProps<{
  code: string
  loggedIn: boolean
  applyUrl?: string
  coupon: {
    code: string
    discount_type: string
    discount_label: string
    min_amount_label: string | null
    starts_at: string | null
    ends_at: string | null
    first_order_only: boolean
    usage_remaining: number | null
    per_user_limit: number | null
    max_discount_label: string | null
    description?: string | null
  } | null
}>()

function applyCoupon() {
  if (!props.applyUrl) return
  router.post(props.applyUrl)
}
</script>

<template>
  <Breadcrumb :items="[
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.store'), href: routes.store },
    { label: t('commerce.coupons.breadcrumb'), current: true },
  ]" />

  <PageHeader :title="t('commerce.coupons.title')" :subtitle="code" />

  <div v-if="coupon" class="max-w-md space-y-4 rounded-lg border p-6">
    <p class="text-2xl font-bold">{{ coupon.discount_label }}</p>
    <p class="text-sm text-muted-foreground">{{ t('commerce.coupons.codeLabel', { code: coupon.code }) }}</p>
    <p v-if="coupon.description" class="text-sm">{{ coupon.description }}</p>
    <ul class="space-y-1 text-sm text-muted-foreground">
      <li v-if="coupon.min_amount_label">{{ t('commerce.coupons.minAmount', { amount: coupon.min_amount_label }) }}</li>
      <li v-if="coupon.starts_at">{{ t('commerce.coupons.startsAt', { at: coupon.starts_at }) }}</li>
      <li v-if="coupon.ends_at">{{ t('commerce.coupons.endsAt', { at: coupon.ends_at }) }}</li>
      <li v-if="coupon.first_order_only">{{ t('commerce.coupons.firstOrderOnly') }}</li>
      <li v-if="coupon.per_user_limit">{{ t('commerce.coupons.perUserLimit', { count: coupon.per_user_limit }) }}</li>
      <li v-if="coupon.max_discount_label">{{ t('commerce.coupons.maxDiscount', { amount: coupon.max_discount_label }) }}</li>
      <li v-if="coupon.usage_remaining !== null">{{ t('commerce.coupons.usageRemaining', { count: coupon.usage_remaining }) }}</li>
    </ul>
    <div class="flex gap-2">
      <Button v-if="loggedIn && applyUrl" type="button" @click="applyCoupon">{{ t('commerce.coupons.applyAndUse') }}</Button>
      <Button v-else-if="!loggedIn" as-child variant="outline">
        <Link :href="routes.signIn">{{ t('commerce.coupons.signInToClaim') }}</Link>
      </Button>
      <Button as-child variant="outline">
        <Link :href="routes.store">{{ t('commerce.coupons.browseProducts') }}</Link>
      </Button>
    </div>
  </div>

  <p v-else class="text-sm text-muted-foreground">{{ t('commerce.coupons.invalid') }}</p>
</template>
