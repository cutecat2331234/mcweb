<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import { adminRoutes } from '@/lib/adminRoutes'
import Table from '@/components/ui/Table.vue'
import TableBody from '@/components/ui/TableBody.vue'
import TableCell from '@/components/ui/TableCell.vue'
import TableHead from '@/components/ui/TableHead.vue'
import TableHeader from '@/components/ui/TableHeader.vue'
import TableRow from '@/components/ui/TableRow.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

export interface Metric {
  label: string
  value: number | string
}

export interface WebhookStatBlock {
  total: number
  success: number
  failed: number
  pending: number
  success_rate: number | null
}

export interface AuditLogItem {
  action: string
  actor: string | null
  created_at: string
}

export interface StoreEventStat {
  event_type: string
  total: number
  success: number
  failed: number
  success_rate: number | null
}

defineProps<{
  metrics: Metric[]
  webhookStats: {
    forum: WebhookStatBlock
    store: WebhookStatBlock
    storeByEvent?: StoreEventStat[]
  }
  webhookFailedLinks: {
    forum: string
    store: string
  }
  recentAuditLogs: AuditLogItem[]
}>()
</script>

<template>
  <PageHeader :title="t('admin.dashboard.title')" :subtitle="t('admin.dashboard.subtitle')" />

  <div class="mb-8 grid gap-4 md:grid-cols-3">
    <div v-for="metric in metrics" :key="metric.label" class="rounded-lg border p-4">
      <p class="text-sm text-muted-foreground">{{ metric.label }}</p>
      <p class="mt-1 text-2xl font-semibold">{{ metric.value }}</p>
    </div>
  </div>

  <h2 class="mb-3 text-sm font-semibold">{{ t('admin.dashboard.webhookTitle') }}</h2>
  <div class="mb-8 grid gap-4 md:grid-cols-2">
    <div class="rounded-lg border p-4">
      <p class="mb-2 text-sm font-medium">{{ t('admin.dashboard.forumSavedSearch') }}</p>
      <p class="text-sm text-muted-foreground">
        {{ t('admin.dashboard.webhookSummary', { total: webhookStats.forum.total, success: webhookStats.forum.success, failed: webhookStats.forum.failed, pending: webhookStats.forum.pending }) }}
      </p>
      <p v-if="webhookStats.forum.success_rate != null" class="mt-1 text-lg font-semibold">
        {{ t('admin.dashboard.successRate', { rate: webhookStats.forum.success_rate }) }}
      </p>
      <Link :href="webhookFailedLinks.forum" class="mt-2 mr-3 inline-block text-sm text-primary hover:underline">{{ t('admin.dashboard.viewFailed') }}</Link>
      <Link :href="adminRoutes.forumWebhookDeliveries" class="mt-2 inline-block text-sm text-muted-foreground hover:underline">{{ t('admin.dashboard.allDeliveries') }}</Link>
    </div>
    <div class="rounded-lg border p-4">
      <p class="mb-2 text-sm font-medium">{{ t('admin.dashboard.storeOrders') }}</p>
      <p class="text-sm text-muted-foreground">
        {{ t('admin.dashboard.webhookSummary', { total: webhookStats.store.total, success: webhookStats.store.success, failed: webhookStats.store.failed, pending: webhookStats.store.pending }) }}
      </p>
      <p v-if="webhookStats.store.success_rate != null" class="mt-1 text-lg font-semibold">
        {{ t('admin.dashboard.successRate', { rate: webhookStats.store.success_rate }) }}
      </p>
      <Link :href="webhookFailedLinks.store" class="mt-2 mr-3 inline-block text-sm text-primary hover:underline">{{ t('admin.dashboard.viewFailed') }}</Link>
      <Link :href="adminRoutes.storeWebhookDeliveries" class="mt-2 inline-block text-sm text-muted-foreground hover:underline">{{ t('admin.dashboard.allDeliveries') }}</Link>
      <div v-if="webhookStats.storeByEvent?.length" class="mt-3 space-y-1 border-t pt-3">
        <p class="text-xs font-medium text-muted-foreground">{{ t('admin.dashboard.byEventType') }}</p>
        <p
          v-for="row in webhookStats.storeByEvent.filter((r) => r.total > 0)"
          :key="row.event_type"
          class="text-xs text-muted-foreground"
        >
          {{ t('admin.dashboard.eventRow', { type: row.event_type, total: row.total }) }}
          <span v-if="row.success_rate != null">{{ t('admin.dashboard.eventSuccessRate', { rate: row.success_rate }) }}</span>
        </p>
      </div>
    </div>
  </div>

  <h2 class="mb-3 text-sm font-semibold">{{ t('admin.dashboard.recentAudit') }}</h2>
  <div v-if="recentAuditLogs.length" class="mb-8 rounded-lg border">
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>{{ t('admin.dashboard.colAction') }}</TableHead>
          <TableHead>{{ t('admin.dashboard.colActor') }}</TableHead>
          <TableHead>{{ t('admin.dashboard.colTime') }}</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        <TableRow v-for="(log, index) in recentAuditLogs" :key="index">
          <TableCell>{{ log.action }}</TableCell>
          <TableCell>{{ log.actor || '—' }}</TableCell>
          <TableCell>{{ log.created_at }}</TableCell>
        </TableRow>
      </TableBody>
    </Table>
  </div>
  <p v-else class="mb-8 text-sm text-muted-foreground">{{ t('admin.dashboard.noAudit') }}</p>

  <h2 class="mb-3 text-sm font-semibold">{{ t('admin.dashboard.quickLinks') }}</h2>
  <div class="flex flex-wrap gap-3">
    <Link :href="adminRoutes.forumSections" class="text-sm hover:underline">{{ t('admin.dashboard.linkForumSections') }}</Link>
    <Link :href="adminRoutes.storeProducts" class="text-sm hover:underline">{{ t('admin.dashboard.linkStoreProducts') }}</Link>
    <Link :href="adminRoutes.site" class="text-sm hover:underline">{{ t('admin.dashboard.linkViewSite') }}</Link>
  </div>
</template>
