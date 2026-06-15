<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Badge from '@/components/ui/Badge.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

defineProps<{
  balanceCents: number
  balanceLabel: string
  transactions: Array<{
    amount_cents: number
    amount_label: string
    credit: boolean
    note: string | null
    created_at: string
    order_url: string | null
  }>
}>()
</script>

<template>
  <PageHeader title="商店余额" :subtitle="`当前余额 ${balanceLabel}`" />

  <p class="mb-6 text-sm text-muted-foreground">
    余额可在结账时自动抵扣订单金额。退款至余额的记录也会显示在下方。
  </p>

  <div class="mb-4 flex gap-3 text-sm">
    <Link :href="routes.storeCheckout" class="text-primary hover:underline">去结账</Link>
    <Link :href="routes.storeOrders" class="text-primary hover:underline">我的订单</Link>
  </div>

  <h2 class="mb-3 text-sm font-semibold">余额变动记录</h2>
  <ul v-if="transactions.length" class="max-w-2xl space-y-2 rounded-lg border p-4 text-sm">
    <li v-for="(tx, index) in transactions" :key="index" class="flex flex-wrap items-center justify-between gap-2 border-b pb-2 last:border-0 last:pb-0">
      <div>
        <Badge :variant="tx.credit ? 'success' : 'default'">{{ tx.credit ? '+' : '−' }}{{ tx.amount_label }}</Badge>
        <span v-if="tx.note" class="ml-2 text-muted-foreground">{{ tx.note }}</span>
      </div>
      <div class="flex items-center gap-2 text-xs text-muted-foreground">
        <Link v-if="tx.order_url" :href="tx.order_url" class="text-primary hover:underline">查看订单</Link>
        <span>{{ tx.created_at }}</span>
      </div>
    </li>
  </ul>
  <p v-else class="text-sm text-muted-foreground">暂无余额变动记录。</p>
</template>
