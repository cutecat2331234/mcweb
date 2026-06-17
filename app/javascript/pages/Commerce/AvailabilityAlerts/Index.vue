<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Badge from '@/components/ui/Badge.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

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
    { label: '首页', href: routes.home },
    { label: '商城', href: routes.store },
    { label: '上架通知', current: true },
  ]" />

  <PageHeader title="上架通知" subtitle="管理你订阅的即将上架商品通知" />

  <div v-if="alerts.length" class="space-y-3">
    <div v-for="alert in alerts" :key="alert.id" class="flex items-center justify-between gap-4 rounded-lg border p-4">
      <div>
        <Link :href="alert.product_url" class="font-medium hover:underline">{{ alert.product_name }}</Link>
        <p class="text-sm text-muted-foreground">订阅于 {{ alert.subscribed_at }}</p>
        <Badge v-if="alert.available" class="mt-1">已上架</Badge>
        <Badge v-else class="mt-1" variant="outline">待上架</Badge>
      </div>
      <Button type="button" size="sm" variant="outline" @click="unsubscribe(alert.unsubscribe_url)">取消订阅</Button>
    </div>
  </div>
  <p v-else class="text-sm text-muted-foreground">暂无上架通知订阅。</p>
</template>
