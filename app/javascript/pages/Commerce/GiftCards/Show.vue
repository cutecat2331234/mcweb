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
  gift_card: {
    code: string
    balance_label: string
    initial_balance_label: string
    expires_at: string | null
    redeemable: boolean
    status_label: string
  } | null
}>()

function applyGiftCard() {
  if (!props.applyUrl) return
  router.post(props.applyUrl)
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '商城', href: routes.store },
    { label: '礼品卡', current: true },
  ]" />

  <PageHeader title="礼品卡" :subtitle="code" />

  <div v-if="gift_card" class="max-w-md space-y-4 rounded-lg border p-6">
    <p class="text-2xl font-bold">{{ gift_card.balance_label }}</p>
    <p class="text-sm text-muted-foreground">代码：<strong>{{ gift_card.code }}</strong></p>
    <ul class="space-y-1 text-sm text-muted-foreground">
      <li>初始面额 {{ gift_card.initial_balance_label }}</li>
      <li>状态：{{ gift_card.status_label }}</li>
      <li v-if="gift_card.expires_at">有效期至 {{ gift_card.expires_at }}</li>
    </ul>
    <div class="flex gap-2">
      <Button v-if="loggedIn && applyUrl && gift_card.redeemable" type="button" @click="applyGiftCard">保存到结账</Button>
      <Button v-else-if="!loggedIn" as-child variant="outline">
        <Link :href="routes.signIn">登录后使用</Link>
      </Button>
      <Button as-child variant="outline">
        <Link :href="routes.store">浏览商品</Link>
      </Button>
    </div>
  </div>

  <p v-else class="text-sm text-muted-foreground">礼品卡代码无效或已过期。</p>
</template>
