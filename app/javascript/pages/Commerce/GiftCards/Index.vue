<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Badge from '@/components/ui/Badge.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

defineProps<{
  gift_cards: Array<{
    code: string
    balance_label: string
    expires_at: string | null
    redeemable: boolean
    status_label: string
    url: string
  }>
}>()
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '商城', href: routes.store },
    { label: '我的礼品卡', current: true },
  ]" />

  <PageHeader title="我的礼品卡" subtitle="已绑定到您账户的礼品卡" />

  <div v-if="gift_cards.length" class="divide-y rounded-lg border">
    <Link
      v-for="card in gift_cards"
      :key="card.code"
      :href="card.url"
      class="flex items-center justify-between gap-4 p-4 no-underline hover:bg-muted/50"
    >
      <div>
        <p class="font-mono font-medium text-foreground">{{ card.code }}</p>
        <p class="text-sm text-muted-foreground">
          余额 {{ card.balance_label }}
          <span v-if="card.expires_at"> · 到期 {{ card.expires_at }}</span>
        </p>
      </div>
      <Badge :variant="card.redeemable ? 'default' : 'secondary'">{{ card.status_label }}</Badge>
    </Link>
  </div>
  <p v-else class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
    暂无礼品卡。在礼品卡页面输入代码并保存到结账即可绑定到您的账户。
  </p>
</template>
