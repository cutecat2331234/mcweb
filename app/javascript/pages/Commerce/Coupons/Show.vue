<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

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
    { label: '首页', href: routes.home },
    { label: '商城', href: routes.store },
    { label: '优惠券', current: true },
  ]" />

  <PageHeader title="优惠券" :subtitle="code" />

  <div v-if="coupon" class="max-w-md space-y-4 rounded-lg border p-6">
    <p class="text-2xl font-bold">{{ coupon.discount_label }}</p>
    <p class="text-sm text-muted-foreground">优惠码：<strong>{{ coupon.code }}</strong></p>
    <p v-if="coupon.description" class="text-sm">{{ coupon.description }}</p>
    <ul class="space-y-1 text-sm text-muted-foreground">
      <li v-if="coupon.min_amount_label">最低消费 {{ coupon.min_amount_label }}</li>
      <li v-if="coupon.starts_at">开始时间 {{ coupon.starts_at }}</li>
      <li v-if="coupon.ends_at">有效期至 {{ coupon.ends_at }}</li>
      <li v-if="coupon.first_order_only">仅限首单使用</li>
      <li v-if="coupon.per_user_limit">每人限用 {{ coupon.per_user_limit }} 次</li>
      <li v-if="coupon.max_discount_label">最高优惠 {{ coupon.max_discount_label }}</li>
      <li v-if="coupon.usage_remaining !== null">剩余 {{ coupon.usage_remaining }} 次</li>
    </ul>
    <div class="flex gap-2">
      <Button v-if="loggedIn && applyUrl" type="button" @click="applyCoupon">领取并使用</Button>
      <Button v-else-if="!loggedIn" as-child variant="outline">
        <Link :href="routes.signIn">登录后领取</Link>
      </Button>
      <Button as-child variant="outline">
        <Link :href="routes.store">浏览商品</Link>
      </Button>
    </div>
  </div>

  <p v-else class="text-sm text-muted-foreground">优惠码无效或已过期。</p>
</template>
