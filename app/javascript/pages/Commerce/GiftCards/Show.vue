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
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.store'), href: routes.store },
    { label: t('commerce.giftCards.showBreadcrumb'), current: true },
  ]" />

  <PageHeader :title="t('commerce.giftCards.showTitle')" :subtitle="code" />

  <div v-if="gift_card" class="max-w-md space-y-4 rounded-lg border p-6">
    <p class="text-2xl font-bold">{{ gift_card.balance_label }}</p>
    <p class="text-sm text-muted-foreground">{{ t('commerce.giftCards.codeLabel', { code: gift_card.code }) }}</p>
    <ul class="space-y-1 text-sm text-muted-foreground">
      <li>{{ t('commerce.giftCards.initialBalance', { amount: gift_card.initial_balance_label }) }}</li>
      <li>{{ t('commerce.giftCards.status', { status: gift_card.status_label }) }}</li>
      <li v-if="gift_card.expires_at">{{ t('commerce.giftCards.expiresAt', { at: gift_card.expires_at }) }}</li>
    </ul>
    <div class="flex gap-2">
      <Button v-if="loggedIn && applyUrl && gift_card.redeemable" type="button" @click="applyGiftCard">{{ t('commerce.giftCards.saveToCheckout') }}</Button>
      <Button v-else-if="!loggedIn" as-child variant="outline">
        <Link :href="routes.signIn">{{ t('commerce.giftCards.signInToUse') }}</Link>
      </Button>
      <Button as-child variant="outline">
        <Link :href="routes.store">{{ t('commerce.giftCards.browseProducts') }}</Link>
      </Button>
    </div>
  </div>

  <p v-else class="text-sm text-muted-foreground">{{ t('commerce.giftCards.invalid') }}</p>
</template>
