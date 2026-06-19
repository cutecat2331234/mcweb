<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Badge from '@/components/ui/Badge.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

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
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.store'), href: routes.store },
    { label: t('commerce.giftCards.breadcrumb'), current: true },
  ]" />

  <PageHeader :title="t('commerce.giftCards.title')" :subtitle="t('commerce.giftCards.subtitle')" />

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
          {{ t('commerce.giftCards.balance', { balance: card.balance_label }) }}
          <span v-if="card.expires_at"> · {{ t('commerce.giftCards.expires', { at: card.expires_at }) }}</span>
        </p>
      </div>
      <Badge :variant="card.redeemable ? 'default' : 'secondary'">{{ card.status_label }}</Badge>
    </Link>
  </div>
  <p v-else class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
    {{ t('commerce.giftCards.empty') }}
  </p>
</template>
