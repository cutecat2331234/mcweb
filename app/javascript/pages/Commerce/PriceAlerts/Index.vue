<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

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
    { label: '首页', href: routes.home },
    { label: '商城', href: routes.store },
    { label: '降价提醒', current: true },
  ]" />

  <PageHeader title="降价提醒" subtitle="管理你订阅的商品降价通知" />

  <div v-if="alerts.length" class="space-y-3">
    <div v-for="alert in alerts" :key="alert.id" class="flex items-center justify-between gap-4 rounded-lg border p-4">
      <div>
        <Link :href="alert.product_url" class="font-medium hover:underline">{{ alert.product_name }}</Link>
        <p v-if="alert.variant_name" class="text-sm text-muted-foreground">规格：{{ alert.variant_name }}</p>
        <p class="text-sm text-muted-foreground">
          订阅价 {{ alert.baseline_price_label }}
          <span class="mx-1">→</span>
          现价 {{ alert.current_price_label }}
        </p>
        <p class="text-xs text-muted-foreground">订阅于 {{ alert.subscribed_at }}</p>
      </div>
      <Button type="button" size="sm" variant="outline" @click="unsubscribe(alert.unsubscribe_url)">取消订阅</Button>
    </div>
  </div>
  <p v-else class="text-sm text-muted-foreground">暂无降价提醒订阅。</p>
</template>
