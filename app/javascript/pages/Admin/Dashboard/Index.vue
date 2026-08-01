<script setup lang="ts">
import { computed } from 'vue'
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

const props = defineProps<{
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

const storeEventRows = computed(() => (
  props.webhookStats.storeByEvent?.filter((row) => row.total > 0) ?? []
))

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

function metricSpan(index: number) {
  const remainder = props.metrics.length % 4
  const fillLastRow = remainder === 2 && index >= props.metrics.length - 2
  return { xs: 1, sm: 1, lg: 1, xl: fillLastRow ? 2 : 1 }
}
</script>

<template>
  <a-space class="admin-dashboard" direction="vertical" :size="16" fill>
    <a-page-header
      :title="t('admin.dashboard.title')"
      :subtitle="t('admin.dashboard.subtitle')"
      :show-back="false"
      class="!px-0"
    />

    <a-grid
      :cols="{ xs: 1, sm: 2, lg: 3, xl: 4 }"
      :col-gap="12"
      :row-gap="12"
      align="stretch"
    >
      <a-grid-item
        v-for="(metric, index) in metrics"
        :key="metric.key"
        :span="metricSpan(index)"
      >
        <a-card
          :class="['arco-stat-card', `mc-admin-surface--${metric.tone}`]"
          size="small"
          :bordered="true"
          :body-style="{ minWidth: 0 }"
          hoverable
        >
          <a-statistic
            v-if="isNumericMetric(metric.value)"
            :title="metric.label"
            :value="metricNumber(metric.value)"
            :precision="metricPrecision(metric.value)"
          />
          <a-space v-else direction="vertical" :size="8" fill>
            <a-typography-text type="secondary">{{ metric.label }}</a-typography-text>
            <a-typography-title
              :heading="4"
              :ellipsis="{ showTooltip: true }"
              class="admin-dashboard__metric-value"
            >
              {{ metric.value }}
            </a-typography-title>
          </a-space>
        </a-card>
      </a-grid-item>
    </a-grid>

    <a-grid
      :cols="24"
      :col-gap="{ xs: 0, sm: 12 }"
      :row-gap="12"
      align="stretch"
    >
      <a-grid-item v-if="minecraftHealth" :span="{ xs: 24, lg: 15, xl: 16 }">
        <a-alert
          :type="minecraftHealth.status === 'ok' ? 'success' : 'warning'"
          :title="t('admin.dashboard.minecraftHealth')"
          show-icon
        >
          <template v-if="minecraftHealth.status === 'ok'">
            {{ t('admin.dashboard.minecraftHealthOk', {
              nodes: minecraftHealth.nodes ?? 0,
              servers: minecraftHealth.managed_servers ?? 0,
            }) }}
          </template>
          <template v-else>
            {{ t('admin.dashboard.minecraftHealthDegraded', {
              stale: minecraftHealth.stale_online_nodes ?? 0,
              mismatch: minecraftHealth.process_mismatch_servers ?? 0,
            }) }}
          </template>
          <a-typography-text v-if="minecraftHealth.message" type="secondary">
            {{ minecraftHealth.message }}
          </a-typography-text>
        </a-alert>
      </a-grid-item>

      <a-grid-item :span="{ xs: 24, lg: minecraftHealth ? 9 : 24, xl: minecraftHealth ? 8 : 24 }">
        <a-card
          class="mc-admin-surface--success"
          :title="t('admin.dashboard.quickLinks')"
          size="small"
          :bordered="true"
        >
          <a-grid :cols="{ xs: 1, sm: 3, lg: 1, xxl: 3 }" :col-gap="8" :row-gap="8">
            <a-grid-item>
              <Link
                :href="adminRoutes.forumSections"
                class="arco-btn arco-btn-secondary arco-btn-size-medium w-full justify-center no-underline"
              >
                {{ t('admin.dashboard.linkForumSections') }}
              </Link>
            </a-grid-item>
            <a-grid-item>
              <Link
                :href="adminRoutes.storeProducts"
                class="arco-btn arco-btn-secondary arco-btn-size-medium w-full justify-center no-underline"
              >
                {{ t('admin.dashboard.linkStoreProducts') }}
              </Link>
            </a-grid-item>
            <a-grid-item>
              <a
                :href="adminRoutes.site"
                data-admin-hard-navigation
                class="arco-btn arco-btn-primary arco-btn-size-medium w-full justify-center no-underline"
              >
                {{ t('admin.dashboard.linkViewSite') }}
              </a>
            </a-grid-item>
          </a-grid>
        </a-card>
      </a-grid-item>
    </a-grid>

    <a-card
      v-if="webhookStats.forum || webhookStats.store"
      class="mc-admin-surface--cyan"
      :title="t('admin.dashboard.webhookTitle')"
      :bordered="true"
    >
      <a-space direction="vertical" :size="16" fill>
      <a-grid :cols="{ xs: 1, xl: 2 }" :col-gap="16" :row-gap="16" align="stretch">
        <a-grid-item v-if="webhookStats.forum">
          <a-space direction="vertical" :size="12" fill>
            <a-row align="center" justify="space-between">
              <a-typography-title :heading="6">
                {{ t('admin.dashboard.forumSavedSearch') }}
              </a-typography-title>
              <a-tag
                :color="webhookStats.forum.failed > 0 ? 'red' : 'green'"
                round
              >
                {{ webhookStats.forum.failed > 0
                  ? t('admin.dashboard.deliveryFailed')
                  : t('admin.dashboard.deliverySuccess') }}
              </a-tag>
            </a-row>
            <a-descriptions :column="{ xs: 1, sm: 2 }" bordered size="small">
              <a-descriptions-item :label="t('admin.dashboard.deliveryTotal')">
                {{ webhookStats.forum.total }}
              </a-descriptions-item>
              <a-descriptions-item :label="t('admin.dashboard.deliverySuccess')">
                {{ webhookStats.forum.success }}
              </a-descriptions-item>
              <a-descriptions-item :label="t('admin.dashboard.deliveryFailed')">
                <a-tag :color="webhookStats.forum.failed > 0 ? 'red' : 'gray'">
                  {{ webhookStats.forum.failed }}
                </a-tag>
              </a-descriptions-item>
              <a-descriptions-item :label="t('admin.dashboard.deliveryPending')">
                {{ webhookStats.forum.pending }}
              </a-descriptions-item>
            </a-descriptions>
            <a-progress
              v-if="webhookStats.forum.success_rate != null"
              :percent="webhookStats.forum.success_rate / 100"
              :status="webhookStats.forum.failed > 0 ? 'warning' : 'success'"
              size="small"
            />
            <a-space wrap size="small">
              <Link
                v-if="webhookFailedLinks.forum"
                :href="webhookFailedLinks.forum"
                class="arco-btn arco-btn-outline arco-btn-status-danger arco-btn-size-medium no-underline"
              >
                {{ t('admin.dashboard.viewFailed') }}
              </Link>
              <Link
                :href="adminRoutes.forumWebhookDeliveries"
                class="arco-btn arco-btn-primary arco-btn-size-medium no-underline"
              >
                {{ t('admin.dashboard.allDeliveries') }}
              </Link>
            </a-space>
          </a-space>
        </a-grid-item>

        <a-grid-item v-if="webhookStats.store">
          <a-space direction="vertical" :size="12" fill>
            <a-row align="center" justify="space-between">
              <a-typography-title :heading="6">
                {{ t('admin.dashboard.storeOrders') }}
              </a-typography-title>
              <a-tag
                :color="webhookStats.store.failed > 0 ? 'red' : 'green'"
                round
              >
                {{ webhookStats.store.failed > 0
                  ? t('admin.dashboard.deliveryFailed')
                  : t('admin.dashboard.deliverySuccess') }}
              </a-tag>
            </a-row>
            <a-descriptions :column="{ xs: 1, sm: 2 }" bordered size="small">
              <a-descriptions-item :label="t('admin.dashboard.deliveryTotal')">
                {{ webhookStats.store.total }}
              </a-descriptions-item>
              <a-descriptions-item :label="t('admin.dashboard.deliverySuccess')">
                {{ webhookStats.store.success }}
              </a-descriptions-item>
              <a-descriptions-item :label="t('admin.dashboard.deliveryFailed')">
                <a-tag :color="webhookStats.store.failed > 0 ? 'red' : 'gray'">
                  {{ webhookStats.store.failed }}
                </a-tag>
              </a-descriptions-item>
              <a-descriptions-item :label="t('admin.dashboard.deliveryPending')">
                {{ webhookStats.store.pending }}
              </a-descriptions-item>
            </a-descriptions>
            <a-progress
              v-if="webhookStats.store.success_rate != null"
              :percent="webhookStats.store.success_rate / 100"
              :status="webhookStats.store.failed > 0 ? 'warning' : 'success'"
              size="small"
            />
            <a-space wrap size="small">
              <Link
                v-if="webhookFailedLinks.store"
                :href="webhookFailedLinks.store"
                class="arco-btn arco-btn-outline arco-btn-status-danger arco-btn-size-medium no-underline"
              >
                {{ t('admin.dashboard.viewFailed') }}
              </Link>
              <Link
                :href="adminRoutes.storeWebhookDeliveries"
                class="arco-btn arco-btn-primary arco-btn-size-medium no-underline"
              >
                {{ t('admin.dashboard.allDeliveries') }}
              </Link>
            </a-space>
          </a-space>
        </a-grid-item>
      </a-grid>

      <a-collapse v-if="storeEventRows.length">
        <a-collapse-item name="event-types" :header="t('admin.dashboard.byEventType')">
          <a-table
            :data="storeEventRows"
            :pagination="false"
            :bordered="{ cell: true }"
            :scroll="{ x: 640 }"
            row-key="event_type"
            size="small"
            stripe
          >
            <template #columns>
              <a-table-column
                :title="t('admin.dashboard.eventType')"
                data-index="event_type"
                :width="180"
                ellipsis
                tooltip
              />
              <a-table-column
                :title="t('admin.dashboard.deliveryTotal')"
                data-index="total"
                :width="100"
              />
              <a-table-column
                :title="t('admin.dashboard.deliverySuccess')"
                data-index="success"
                :width="110"
              />
              <a-table-column
                :title="t('admin.dashboard.deliveryFailed')"
                data-index="failed"
                :width="110"
              />
              <a-table-column
                :title="t('admin.dashboard.deliverySuccessRate')"
                :width="130"
              >
                <template #cell="{ record }">
                  {{ record.success_rate == null ? '—' : `${record.success_rate}%` }}
                </template>
              </a-table-column>
            </template>
          </a-table>
        </a-collapse-item>
      </a-collapse>
      </a-space>
    </a-card>

    <a-card
      class="mc-admin-surface--primary"
      :title="t('admin.dashboard.recentAudit')"
      :bordered="true"
    >
      <a-table
        :data="recentAuditLogs"
        :pagination="false"
        :bordered="{ cell: true }"
        :scroll="{ x: 720 }"
        row-key="created_at"
        size="small"
        stripe
      >
        <template #columns>
          <a-table-column
            :title="t('admin.dashboard.colAction')"
            data-index="action"
            :width="300"
            ellipsis
            tooltip
          />
          <a-table-column
            :title="t('admin.dashboard.colActor')"
            data-index="actor"
            :width="180"
            ellipsis
            tooltip
          >
            <template #cell="{ record }">{{ record.actor || '—' }}</template>
          </a-table-column>
          <a-table-column
            :title="t('admin.dashboard.colTime')"
            data-index="created_at"
            :width="220"
            ellipsis
            tooltip
          />
        </template>
        <template #empty>
          <a-empty :description="t('admin.dashboard.noAudit')" />
        </template>
      </a-table>
    </a-card>
  </a-space>
</template>

<style scoped>
.admin-dashboard :deep(.arco-statistic-title) {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.admin-dashboard :deep(.arco-card-body) {
  min-width: 0;
}

.admin-dashboard__metric-value {
  margin: 0;
}
</style>
