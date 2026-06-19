<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Badge from '@/components/ui/Badge.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

defineProps<{
  alerts: Array<{
    id: number
    product_name: string
    product_url: string
    available: boolean
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
    { label: t('commerce.availabilityAlerts.breadcrumb'), current: true },
  ]" />

  <PageHeader :title="t('commerce.availabilityAlerts.title')" :subtitle="t('commerce.availabilityAlerts.subtitle')" />

  <div v-if="alerts.length" class="space-y-3">
    <div v-for="alert in alerts" :key="alert.id" class="flex items-center justify-between gap-4 rounded-lg border p-4">
      <div>
        <Link :href="alert.product_url" class="font-medium hover:underline">{{ alert.product_name }}</Link>
        <p class="text-sm text-muted-foreground">{{ t('commerce.availabilityAlerts.subscribedAt', { at: alert.subscribed_at }) }}</p>
        <Badge v-if="alert.available" class="mt-1">{{ t('commerce.availabilityAlerts.available') }}</Badge>
        <Badge v-else class="mt-1" variant="outline">{{ t('commerce.availabilityAlerts.pending') }}</Badge>
      </div>
      <Button type="button" size="sm" variant="outline" @click="unsubscribe(alert.unsubscribe_url)">{{ t('commerce.availabilityAlerts.unsubscribe') }}</Button>
    </div>
  </div>
  <p v-else class="text-sm text-muted-foreground">{{ t('commerce.availabilityAlerts.empty') }}</p>
</template>
