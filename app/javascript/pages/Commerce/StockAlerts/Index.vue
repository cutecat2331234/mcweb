<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Badge from '@/components/ui/Badge.vue'
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
    in_stock?: boolean
    subscribed_at: string
    add_to_cart_url?: string | null
    unsubscribe_url: string
  }>
}>()

function addToCart(url: string) {
  router.post(url)
}

function unsubscribe(url: string) {
  router.delete(url, { preserveScroll: true })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.store'), href: routes.store },
    { label: t('commerce.stockAlerts.breadcrumb'), current: true },
  ]" />

  <PageHeader :title="t('commerce.stockAlerts.title')" :subtitle="t('commerce.stockAlerts.subtitle')" />

  <div v-if="alerts.length" class="space-y-3">
    <div v-for="alert in alerts" :key="alert.id" class="flex items-center justify-between gap-4 rounded-lg border p-4">
      <div>
        <Link :href="alert.product_url" class="font-medium hover:underline">{{ alert.product_name }}</Link>
        <p v-if="alert.variant_name" class="text-sm text-muted-foreground">{{ t('commerce.stockAlerts.variant', { name: alert.variant_name }) }}</p>
        <p class="text-xs text-muted-foreground">{{ t('commerce.stockAlerts.subscribedAt', { at: alert.subscribed_at }) }}</p>
        <Badge v-if="alert.in_stock" variant="success" class="mt-1">{{ t('commerce.stockAlerts.inStock') }}</Badge>
      </div>
      <div class="flex gap-2">
        <Button v-if="alert.add_to_cart_url" type="button" size="sm" @click="addToCart(alert.add_to_cart_url)">{{ t('commerce.stockAlerts.addToCart') }}</Button>
        <Button type="button" size="sm" variant="outline" @click="unsubscribe(alert.unsubscribe_url)">{{ t('commerce.stockAlerts.unsubscribe') }}</Button>
      </div>
    </div>
  </div>
  <p v-else class="text-sm text-muted-foreground">{{ t('commerce.stockAlerts.empty') }}</p>
</template>
