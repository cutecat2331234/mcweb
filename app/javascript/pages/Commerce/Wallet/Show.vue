<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Badge from '@/components/ui/Badge.vue'
import Button from '@/components/ui/Button.vue'
import Table from '@/components/ui/Table.vue'
import TableBody from '@/components/ui/TableBody.vue'
import TableCell from '@/components/ui/TableCell.vue'
import TableHead from '@/components/ui/TableHead.vue'
import TableHeader from '@/components/ui/TableHeader.vue'
import TableRow from '@/components/ui/TableRow.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

defineProps<{
  balanceCents: number
  balanceLabel: string
  memberships?: Array<{
    slug: string
    name: string
    color?: string | null
    icon?: string | null
    expires_label?: string
    permanent?: boolean
  }>
  transactions: Array<{
    ledger_id: string
    amount_cents: number
    amount_label: string
    credit: boolean
    source_label: string
    note: string | null
    balance_before_label: string | null
    balance_after_label: string | null
    order_number: string | null
    created_at: string
    order_url: string | null
  }>
  pagination: {
    has_more: boolean
    next_url: string | null
  }
}>()
</script>

<template>
  <PageHeader :title="t('commerce.wallet.title')" :subtitle="t('commerce.wallet.subtitle', { balance: balanceLabel })" />

  <p class="mb-6 text-sm text-muted-foreground">
    {{ t('commerce.wallet.description') }}
  </p>

  <div v-if="memberships != null" class="mb-6 max-w-2xl rounded-lg border p-4">
    <h2 class="mb-3 text-sm font-semibold">{{ t('commerce.wallet.myMemberships') }}</h2>
    <div v-if="memberships.length" class="flex flex-wrap gap-2">
      <Badge
        v-for="membership in memberships"
        :key="membership.slug"
        variant="outline"
        :style="membership.color ? { borderColor: membership.color, color: membership.color } : undefined"
      >
        {{ membership.icon }} {{ membership.name }}
        <span class="text-muted-foreground">· {{ membership.permanent ? t('commerce.memberships.permanent') : membership.expires_label }}</span>
      </Badge>
    </div>
    <p v-else class="text-sm text-muted-foreground">{{ t('commerce.wallet.noMemberships') }}</p>
  </div>

  <div class="mb-4 flex gap-3 text-sm">
    <Link :href="routes.storeCheckout" class="text-primary hover:underline">{{ t('commerce.wallet.checkout') }}</Link>
    <Link :href="routes.storeOrders" class="text-primary hover:underline">{{ t('commerce.wallet.myOrders') }}</Link>
  </div>

  <h2 class="mb-3 text-sm font-semibold">{{ t('commerce.wallet.transactions') }}</h2>
  <div v-if="transactions.length" class="max-w-5xl overflow-hidden rounded-lg border bg-card">
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>{{ t('commerce.wallet.ledgerId') }}</TableHead>
          <TableHead>{{ t('commerce.wallet.change') }}</TableHead>
          <TableHead>{{ t('commerce.wallet.source') }}</TableHead>
          <TableHead>{{ t('commerce.wallet.balance') }}</TableHead>
          <TableHead>{{ t('commerce.wallet.recordedAt') }}</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        <TableRow v-for="tx in transactions" :key="tx.ledger_id">
          <TableCell class="whitespace-nowrap font-mono text-xs">{{ tx.ledger_id }}</TableCell>
          <TableCell class="min-w-40">
            <Badge :variant="tx.credit ? 'success' : 'default'">{{ tx.credit ? '+' : '−' }}{{ tx.amount_label }}</Badge>
            <p v-if="tx.note" class="mt-1 max-w-80 text-xs text-muted-foreground">{{ tx.note }}</p>
          </TableCell>
          <TableCell class="min-w-32">
            <p>{{ tx.source_label }}</p>
            <Link v-if="tx.order_url" :href="tx.order_url" class="text-xs text-primary hover:underline">
              {{ t('commerce.wallet.viewOrderNumber', { number: tx.order_number }) }}
            </Link>
          </TableCell>
          <TableCell class="whitespace-nowrap text-xs text-muted-foreground">
            <template v-if="tx.balance_before_label && tx.balance_after_label">
              {{ tx.balance_before_label }} → {{ tx.balance_after_label }}
            </template>
            <template v-else>{{ t('commerce.wallet.legacyBalanceUnavailable') }}</template>
          </TableCell>
          <TableCell class="whitespace-nowrap text-xs text-muted-foreground">{{ tx.created_at }}</TableCell>
        </TableRow>
      </TableBody>
    </Table>
  </div>
  <p v-else class="text-sm text-muted-foreground">{{ t('commerce.wallet.empty') }}</p>

  <Button v-if="pagination.has_more && pagination.next_url" as-child variant="outline" class="mt-4">
    <Link :href="pagination.next_url" preserve-scroll>{{ t('commerce.wallet.olderTransactions') }}</Link>
  </Button>
</template>
