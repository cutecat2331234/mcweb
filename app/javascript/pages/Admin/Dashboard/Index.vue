<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { adminRoutes } from '@/lib/adminRoutes'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

export interface Metric {
  key: string
  tone: 'primary' | 'cyan' | 'violet' | 'success' | 'warning' | 'danger'
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

export interface MinecraftHealth {
  status: string
  nodes?: number
  managed_servers?: number
  stale_online_nodes?: number
  process_mismatch_servers?: number
  message?: string
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
  minecraftHealth?: MinecraftHealth
  webhookStats: {
    forum: WebhookStatBlock | null
    store: WebhookStatBlock | null
    storeByEvent?: StoreEventStat[]
  }
  webhookFailedLinks: {
    forum: string | null
    store: string | null
  }
  recentAuditLogs: AuditLogItem[]
}>()

function metricNumber(value: Metric['value']) {
  const numeric = typeof value === 'number' ? value : Number(value)
  return Number.isFinite(numeric) ? numeric : 0
}

function isNumericMetric(value: Metric['value']) {
  return Number.isFinite(typeof value === 'number' ? value : Number(value))
}

function metricPrecision(value: Metric['value']) {
  if (typeof value !== 'string' || !value.includes('.')) return 0
  return value.split('.')[1]?.length ?? 0
}
</script>

<template>
  <div class="admin-dashboard">
    <a-page-header
      :title="t('admin.dashboard.title')"
      :subtitle="t('admin.dashboard.subtitle')"
      :show-back="false"
      class="mb-4 !px-0"
    />

    <a-row :gutter="[16, 16]" class="mb-6">
      <a-col
        v-for="metric in metrics"
        :key="metric.key"
        :xs="24"
        :sm="12"
        :lg="8"
      >
        <a-card
          :class="['arco-stat-card', `mc-admin-surface--${metric.tone}`]"
          :bordered="true"
          hoverable
        >
          <a-statistic
            v-if="isNumericMetric(metric.value)"
            :title="metric.label"
            :value="metricNumber(metric.value)"
            :precision="metricPrecision(metric.value)"
          />
          <div v-else class="arco-statistic">
            <div class="arco-statistic-title">{{ metric.label }}</div>
            <div class="arco-statistic-content">{{ metric.value }}</div>
          </div>
        </a-card>
      </a-col>
    </a-row>

    <a-alert
      v-if="minecraftHealth"
      class="mb-6"
      :type="minecraftHealth.status === 'ok' ? 'success' : 'warning'"
      :title="t('admin.dashboard.minecraftHealth')"
      show-icon
    >
      <template v-if="minecraftHealth.status === 'ok'">
        {{ t('admin.dashboard.minecraftHealthOk', { nodes: minecraftHealth.nodes ?? 0, servers: minecraftHealth.managed_servers ?? 0 }) }}
      </template>
      <template v-else>
        {{ t('admin.dashboard.minecraftHealthDegraded', { stale: minecraftHealth.stale_online_nodes ?? 0, mismatch: minecraftHealth.process_mismatch_servers ?? 0 }) }}
      </template>
      <p v-if="minecraftHealth.message" class="mt-1">{{ minecraftHealth.message }}</p>
    </a-alert>

    <section v-if="webhookStats.forum || webhookStats.store" class="mb-6">
      <h2 class="mb-3 text-base font-semibold">{{ t('admin.dashboard.webhookTitle') }}</h2>
      <a-row :gutter="[16, 16]">
        <a-col v-if="webhookStats.forum" :xs="24" :lg="12">
          <a-card
            class="mc-admin-surface--cyan"
            :title="t('admin.dashboard.forumSavedSearch')"
            :bordered="true"
          >
            <p class="text-sm text-[var(--color-text-3)]">
              {{ t('admin.dashboard.webhookSummary', { total: webhookStats.forum.total, success: webhookStats.forum.success, failed: webhookStats.forum.failed, pending: webhookStats.forum.pending }) }}
            </p>
            <p
              v-if="webhookStats.forum.success_rate != null"
              class="mt-3 text-lg font-semibold"
            >
              {{ t('admin.dashboard.successRate', { rate: webhookStats.forum.success_rate }) }}
            </p>
            <a-space class="mt-4" wrap>
              <Link
                v-if="webhookFailedLinks.forum"
                :href="webhookFailedLinks.forum"
                class="text-sm text-[rgb(var(--primary-6))] no-underline hover:underline"
              >
                {{ t('admin.dashboard.viewFailed') }}
              </Link>
              <Link
                :href="adminRoutes.forumWebhookDeliveries"
                class="text-sm text-[var(--color-text-3)] no-underline hover:underline"
              >
                {{ t('admin.dashboard.allDeliveries') }}
              </Link>
            </a-space>
          </a-card>
        </a-col>

        <a-col v-if="webhookStats.store" :xs="24" :lg="12">
          <a-card
            class="mc-admin-surface--violet"
            :title="t('admin.dashboard.storeOrders')"
            :bordered="true"
          >
            <p class="text-sm text-[var(--color-text-3)]">
              {{ t('admin.dashboard.webhookSummary', { total: webhookStats.store.total, success: webhookStats.store.success, failed: webhookStats.store.failed, pending: webhookStats.store.pending }) }}
            </p>
            <p
              v-if="webhookStats.store.success_rate != null"
              class="mt-3 text-lg font-semibold"
            >
              {{ t('admin.dashboard.successRate', { rate: webhookStats.store.success_rate }) }}
            </p>
            <a-space class="mt-4" wrap>
              <Link
                v-if="webhookFailedLinks.store"
                :href="webhookFailedLinks.store"
                class="text-sm text-[rgb(var(--primary-6))] no-underline hover:underline"
              >
                {{ t('admin.dashboard.viewFailed') }}
              </Link>
              <Link
                :href="adminRoutes.storeWebhookDeliveries"
                class="text-sm text-[var(--color-text-3)] no-underline hover:underline"
              >
                {{ t('admin.dashboard.allDeliveries') }}
              </Link>
            </a-space>

            <div v-if="webhookStats.storeByEvent?.some((row) => row.total > 0)" class="mt-4">
              <a-divider />
              <p class="mb-2 text-xs font-medium text-[var(--color-text-3)]">
                {{ t('admin.dashboard.byEventType') }}
              </p>
              <a-list size="small" :bordered="false">
                <a-list-item
                  v-for="row in webhookStats.storeByEvent.filter((item) => item.total > 0)"
                  :key="row.event_type"
                >
                  <span class="text-xs text-[var(--color-text-3)]">
                    {{ t('admin.dashboard.eventRow', { type: row.event_type, total: row.total }) }}
                    <span v-if="row.success_rate != null">
                      {{ t('admin.dashboard.eventSuccessRate', { rate: row.success_rate }) }}
                    </span>
                  </span>
                </a-list-item>
              </a-list>
            </div>
          </a-card>
        </a-col>
      </a-row>
    </section>

    <a-card
      class="mb-6 mc-admin-surface--primary"
      :title="t('admin.dashboard.recentAudit')"
      :bordered="true"
    >
      <a-table
        :data="recentAuditLogs"
        :pagination="false"
        :bordered="{ cell: true }"
        row-key="created_at"
        stripe
      >
        <template #columns>
          <a-table-column :title="t('admin.dashboard.colAction')" data-index="action" />
          <a-table-column :title="t('admin.dashboard.colActor')" data-index="actor">
            <template #cell="{ record }">{{ record.actor || '—' }}</template>
          </a-table-column>
          <a-table-column :title="t('admin.dashboard.colTime')" data-index="created_at" />
        </template>
        <template #empty>
          <a-empty :description="t('admin.dashboard.noAudit')" />
        </template>
      </a-table>
    </a-card>

    <a-card
      class="mc-admin-surface--success"
      :title="t('admin.dashboard.quickLinks')"
      :bordered="true"
    >
      <a-space wrap :size="[16, 8]">
        <Link
          :href="adminRoutes.forumSections"
          class="arco-btn arco-btn-outline arco-btn-size-medium no-underline"
        >
          {{ t('admin.dashboard.linkForumSections') }}
        </Link>
        <Link
          :href="adminRoutes.storeProducts"
          class="arco-btn arco-btn-outline arco-btn-size-medium no-underline"
        >
          {{ t('admin.dashboard.linkStoreProducts') }}
        </Link>
        <a
          :href="adminRoutes.site"
          data-admin-hard-navigation
          class="arco-btn arco-btn-primary arco-btn-size-medium no-underline"
        >
          {{ t('admin.dashboard.linkViewSite') }}
        </a>
      </a-space>
    </a-card>
  </div>
</template>

<style scoped>
.admin-dashboard :deep(.arco-statistic-title) {
  color: var(--color-text-3);
}

.admin-dashboard :deep(.arco-card-body) {
  min-width: 0;
}
</style>
