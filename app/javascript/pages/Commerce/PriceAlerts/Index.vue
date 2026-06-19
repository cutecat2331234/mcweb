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

defineProps<{
  alerts: Array<{
    id: number
    product_name: string
    variant_name: string | null
    product_url: string
    baseline_price_label: string
    current_price_label: string
    subscribed_at: string
    unsubscribe_url: string
  }>
}>()

function unsubscribe(url: string) {
  router.delete(url, { preserveScroll: true })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.store'), href: routes.store },
    { label: t('commerce.priceAlerts.breadcrumb'), current: true },
  ]" />

  <PageHeader :title="t('commerce.priceAlerts.title')" :subtitle="t('commerce.priceAlerts.subtitle')" />

  <div v-if="alerts.length" class="space-y-3">
    <div v-for="alert in alerts" :key="alert.id" class="flex items-center justify-between gap-4 rounded-lg border p-4">
      <div>
        <Link :href="alert.product_url" class="font-medium hover:underline">{{ alert.product_name }}</Link>
        <p v-if="alert.variant_name" class="text-sm text-muted-foreground">{{ t('commerce.priceAlerts.variant', { name: alert.variant_name }) }}</p>
        <p class="text-sm text-muted-foreground">
          {{ t('commerce.priceAlerts.priceChange', { baseline: alert.baseline_price_label, current: alert.current_price_label }) }}
        </p>
        <p class="text-xs text-muted-foreground">{{ t('commerce.priceAlerts.subscribedAt', { at: alert.subscribed_at }) }}</p>
      </div>
      <Button type="button" size="sm" variant="outline" @click="unsubscribe(alert.unsubscribe_url)">{{ t('commerce.priceAlerts.unsubscribe') }}</Button>
    </div>
  </div>
  <p v-else class="text-sm text-muted-foreground">{{ t('commerce.priceAlerts.empty') }}</p>
</template>
