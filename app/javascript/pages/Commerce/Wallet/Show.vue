<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Badge from '@/components/ui/Badge.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

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
  <PageHeader :title="t('commerce.wallet.title')" :subtitle="t('commerce.wallet.subtitle', { balance: balanceLabel })" />

  <p class="mb-6 text-sm text-muted-foreground">
    {{ t('commerce.wallet.description') }}
  </p>

  <div class="mb-4 flex gap-3 text-sm">
    <Link :href="routes.storeCheckout" class="text-primary hover:underline">{{ t('commerce.wallet.checkout') }}</Link>
    <Link :href="routes.storeOrders" class="text-primary hover:underline">{{ t('commerce.wallet.myOrders') }}</Link>
  </div>

  <h2 class="mb-3 text-sm font-semibold">{{ t('commerce.wallet.transactions') }}</h2>
  <ul v-if="transactions.length" class="max-w-2xl space-y-2 rounded-lg border p-4 text-sm">
    <li v-for="(tx, index) in transactions" :key="index" class="flex flex-wrap items-center justify-between gap-2 border-b pb-2 last:border-0 last:pb-0">
      <div>
        <Badge :variant="tx.credit ? 'success' : 'default'">{{ tx.credit ? '+' : '−' }}{{ tx.amount_label }}</Badge>
        <span v-if="tx.note" class="ml-2 text-muted-foreground">{{ tx.note }}</span>
      </div>
      <div class="flex items-center gap-2 text-xs text-muted-foreground">
        <Link v-if="tx.order_url" :href="tx.order_url" class="text-primary hover:underline">{{ t('commerce.wallet.viewOrder') }}</Link>
        <span>{{ tx.created_at }}</span>
      </div>
    </li>
  </ul>
  <p v-else class="text-sm text-muted-foreground">{{ t('commerce.wallet.empty') }}</p>
</template>
