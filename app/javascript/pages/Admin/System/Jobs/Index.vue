<script setup lang="ts">
import { ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { router } from '@inertiajs/vue3'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

const { t, locale } = useI18n()
const metricsLoading = ref(false)

type MetricStatus = 'healthy' | 'warning' | 'critical'

type OperationsMetrics = {
  available: boolean
  error_code?: string | null
  range: string
  ranges: string[]
  generated_at: string
  from?: string | null
  to?: string | null
  resolution_seconds?: number | null
  row_budget: number
  row_count: number
  truncated: boolean
  thresholds: Record<string, number>
  summary: {
    request_count?: number
    request_average_ms?: number
    request_max_ms?: number
    server_errors?: number
    request_error_rate_percent?: number
    slow_query_count?: number
    slow_query_max_ms?: number
    job_count?: number
    job_average_ms?: number
    job_failures?: number
    job_failure_rate_percent?: number
    mail_deliveries?: number
    mail_failures?: number
    mail_failure_rate_percent?: number
    payment_webhooks?: number
    payment_webhook_failures?: number
    uploads?: number
    upload_failures?: number
    scans?: number
    scan_failures?: number
    queue_enqueued?: number
    queue_oldest_wait_seconds?: number
    queue_utilization_percent?: number
    queue_worker_count?: number
  }
  comparison: Record<string, number | null>
  checks: Array<{
    key: string
    status: MetricStatus
    unit: 'ms' | 'percent' | 'count'
    value: number
    threshold: number
    percent: number
  }>
  series: Array<{
    bucket_at: string
    request_count: number
    request_average_ms: number
    server_errors: number
    slow_queries: number
    job_count: number
    job_failures: number
    queue_enqueued: number
    queue_utilization_percent: number
  }>
}

const props = defineProps<{
  dashboardUrl: string
  metricsUrl: string
  developerMode: {
    enabled: boolean
    profile?: string | null
  }
  automaticRegistration: boolean
  queueSnapshot: {
    available: boolean
    adapter: string
    status: 'healthy' | 'warning' | 'error' | 'unavailable' | 'local'
    error_code?: string
    worker_count: number
    busy_workers: number
    concurrency: number
    utilization_percent: number
    enqueued: number
    retry_count: number
    scheduled_count: number
    dead_count: number
    failed_count: number
    processed_count: number
    oldest_wait_seconds: number
    backlog_warning: number
    latency_warning_seconds: number
    queues: Array<{
      name: string
      size: number
      latency_seconds: number
    }>
  }
  workerHeartbeat: {
    available: boolean
    status: 'healthy' | 'stale' | 'missing' | 'unavailable'
    fresh_count: number
    latest_at?: string | null
  }
  operationsMetrics: OperationsMetrics
}>()

function queueStatusColor(status: string) {
  if (status === 'healthy') return 'green'
  if (status === 'warning') return 'orange'
  if (status === 'error' || status === 'unavailable') return 'red'
  return 'arcoblue'
}

function queueAlertType(status: string) {
  if (status === 'error' || status === 'unavailable') return 'error'
  if (status === 'warning') return 'warning'
  return 'info'
}

function formatDate(value?: string | null) {
  if (!value) return t('common.notAvailable')
  return new Intl.DateTimeFormat(locale.value, {
    dateStyle: 'medium',
    timeStyle: 'medium',
  }).format(new Date(value))
}

function selectMetricsRange(value: string | number | boolean) {
  const range = String(value)
  if (range === props.operationsMetrics.range || metricsLoading.value) return

  router.get(
    props.metricsUrl,
    { range },
    {
      only: ['operationsMetrics'],
      preserveState: true,
      preserveScroll: true,
      replace: true,
      onStart: () => {
        metricsLoading.value = true
      },
      onFinish: () => {
        metricsLoading.value = false
      },
    },
  )
}

function metricStatusColor(status: MetricStatus) {
  if (status === 'critical') return 'red'
  if (status === 'warning') return 'orange'
  return 'green'
}

function metricProgressStatus(status: MetricStatus) {
  if (status === 'critical') return 'danger'
  if (status === 'warning') return 'warning'
  return 'success'
}

function deltaColor(value?: number | null) {
  if (value == null || value === 0) return 'gray'
  return value > 0 ? 'orange' : 'green'
}

function formatDelta(value?: number | null) {
  if (value == null) return t('admin.jobsPage.metrics.noComparison')
  const prefix = value > 0 ? '+' : ''
  return t('admin.jobsPage.metrics.delta', {
    value: `${prefix}${value.toFixed(1)}`,
  })
}

function metricValue(key: string) {
  return props.operationsMetrics.summary[key as keyof OperationsMetrics['summary']] ?? 0
}

function formatCheckValue(check: OperationsMetrics['checks'][number]) {
  return t(`admin.jobsPage.metrics.checkValues.${check.unit}`, {
    value: check.value,
    threshold: check.threshold,
  })
}
</script>

<template>
  <a-space direction="vertical" :size="16" fill data-testid="admin-jobs-page">
    <a-page-header
      :title="t('admin.jobsPage.title')"
      :subtitle="t('admin.jobsPage.subtitle')"
      :show-back="false"
      data-testid="admin-jobs-header"
    />

    <a-alert
      v-if="developerMode.enabled"
      type="warning"
      show-icon
      :title="t('admin.jobsPage.developerModeTitle')"
    >
      {{ t('admin.jobsPage.developerModeDescription') }}
    </a-alert>

    <a-alert
      v-if="queueSnapshot.status !== 'healthy' && queueSnapshot.status !== 'local'"
      :type="queueAlertType(queueSnapshot.status)"
      show-icon
      :title="t(`admin.jobsPage.queue.status.${queueSnapshot.status}`)"
    >
      {{
        queueSnapshot.status === 'warning'
          ? t('admin.jobsPage.queue.warningDescription', {
              backlog: queueSnapshot.enqueued,
              wait: queueSnapshot.oldest_wait_seconds,
            })
          : t('admin.jobsPage.queue.unavailableDescription')
      }}
    </a-alert>

    <a-grid :cols="{ xs: 1, lg: 2 }" :col-gap="16" :row-gap="16">
      <a-grid-item>
        <a-card :title="t('admin.jobsPage.schedulerTitle')" :bordered="true">
        <a-descriptions :column="1" bordered size="small">
          <a-descriptions-item :label="t('admin.jobsPage.runtimeMode')">
            <a-space wrap>
              <a-tag :color="developerMode.enabled ? 'orange' : 'green'">
                {{
                  developerMode.enabled
                    ? t('admin.jobsPage.developerMode')
                    : t('admin.jobsPage.standardMode')
                }}
              </a-tag>
              <a-typography-text v-if="developerMode.profile">
                {{ developerMode.profile }}
              </a-typography-text>
            </a-space>
          </a-descriptions-item>
          <a-descriptions-item :label="t('admin.jobsPage.automaticRegistration')">
            <a-tag :color="automaticRegistration ? 'green' : 'orange'">
              {{
                automaticRegistration
                  ? t('admin.jobsPage.running')
                  : t('admin.jobsPage.paused')
              }}
            </a-tag>
          </a-descriptions-item>
          <a-descriptions-item :label="t('admin.jobsPage.manualExecution')">
            <a-tag color="green">{{ t('admin.jobsPage.available') }}</a-tag>
          </a-descriptions-item>
        </a-descriptions>
        </a-card>
      </a-grid-item>

      <a-grid-item>
        <a-card :title="t('admin.jobsPage.dashboardTitle')" :bordered="true">
          <a-space direction="vertical" :size="12" fill>
            <a-typography-paragraph>
              {{ t('admin.jobsPage.dashboardDescription') }}
            </a-typography-paragraph>
            <a-button type="primary" :href="dashboardUrl" long data-admin-hard-navigation>
              {{ t('admin.jobsPage.openDashboard') }}
            </a-button>
          </a-space>
        </a-card>
      </a-grid-item>
    </a-grid>

    <a-card
      :title="t('admin.jobsPage.queue.title')"
      :bordered="true"
    >
      <template #extra>
        <a-space wrap>
          <a-tag color="arcoblue">{{ queueSnapshot.adapter }}</a-tag>
          <a-tag :color="queueStatusColor(queueSnapshot.status)">
            {{ t(`admin.jobsPage.queue.status.${queueSnapshot.status}`) }}
          </a-tag>
        </a-space>
      </template>

      <a-descriptions
        :column="{ xs: 2, sm: 2, xl: 5 }"
        layout="vertical"
        bordered
        size="small"
      >
        <a-descriptions-item :label="t('admin.jobsPage.queue.heartbeats')">
          <a-space direction="vertical" :size="4" fill>
            <a-statistic :value="workerHeartbeat.fresh_count" />
            <a-space wrap size="small">
              <a-tag
                :color="workerHeartbeat.status === 'healthy' ? 'green' : 'orange'"
              >
                {{ t(`admin.jobsPage.queue.heartbeatStatus.${workerHeartbeat.status}`) }}
              </a-tag>
              <a-tooltip :content="formatDate(workerHeartbeat.latest_at)">
                <a-typography-text type="secondary">
                  {{ t('admin.jobsPage.queue.lastSeen') }}
                </a-typography-text>
              </a-tooltip>
            </a-space>
          </a-space>
        </a-descriptions-item>

        <a-descriptions-item :label="t('admin.jobsPage.queue.workers')">
          <a-space direction="vertical" :size="4" fill>
            <a-statistic :value="queueSnapshot.worker_count">
              <template #suffix>
                <a-typography-text type="secondary">
                  / {{ queueSnapshot.concurrency }}
                </a-typography-text>
              </template>
            </a-statistic>
            <a-progress
              :percent="queueSnapshot.utilization_percent / 100"
              :status="queueSnapshot.utilization_percent >= 90 ? 'warning' : 'normal'"
              size="small"
              aria-hidden="true"
            />
          </a-space>
        </a-descriptions-item>

        <a-descriptions-item :label="t('admin.jobsPage.queue.enqueued')">
          <a-space direction="vertical" :size="4" fill>
            <a-statistic :value="queueSnapshot.enqueued" />
            <a-typography-text type="secondary" data-testid="volatile-timestamp">
              {{ t('admin.jobsPage.queue.warningAt', { count: queueSnapshot.backlog_warning }) }}
            </a-typography-text>
          </a-space>
        </a-descriptions-item>

        <a-descriptions-item :label="t('admin.jobsPage.queue.oldestWait')">
          <a-space direction="vertical" :size="4" fill>
            <a-statistic
              :value="queueSnapshot.oldest_wait_seconds"
              :precision="1"
              :suffix="t('admin.jobsPage.queue.seconds')"
            />
            <a-typography-text type="secondary">
              {{
                t('admin.jobsPage.queue.warningAtSeconds', {
                  count: queueSnapshot.latency_warning_seconds,
                })
              }}
            </a-typography-text>
          </a-space>
        </a-descriptions-item>

        <a-descriptions-item :label="t('admin.jobsPage.queue.failures')">
          <a-space direction="vertical" :size="4" fill>
            <a-statistic :value="queueSnapshot.failed_count" />
            <a-space wrap size="small">
              <a-tag color="orange">
                {{ t('admin.jobsPage.queue.retries', { count: queueSnapshot.retry_count }) }}
              </a-tag>
              <a-tag :color="queueSnapshot.dead_count ? 'red' : 'green'">
                {{ t('admin.jobsPage.queue.dead', { count: queueSnapshot.dead_count }) }}
              </a-tag>
            </a-space>
          </a-space>
        </a-descriptions-item>
      </a-descriptions>

      <a-divider />

      <a-table
        :data="queueSnapshot.queues"
        :pagination="false"
        :bordered="{ cell: true }"
        stripe
        row-key="name"
      >
        <template #columns>
          <a-table-column
            data-index="name"
            :title="t('admin.jobsPage.queue.queueName')"
          />
          <a-table-column
            data-index="size"
            :title="t('admin.jobsPage.queue.queueSize')"
          />
          <a-table-column
            data-index="latency_seconds"
            :title="t('admin.jobsPage.queue.queueLatency')"
          >
            <template #cell="{ record }">
              <a-tag
                :color="
                  record.latency_seconds >= queueSnapshot.latency_warning_seconds
                    ? 'orange'
                    : 'green'
                "
              >
                {{ t('admin.jobsPage.queue.secondsValue', { count: record.latency_seconds }) }}
              </a-tag>
            </template>
          </a-table-column>
        </template>
        <template #empty>
          <a-empty :description="t('admin.jobsPage.queue.noQueues')" />
        </template>
      </a-table>
    </a-card>

    <a-card
      :title="t('admin.jobsPage.metrics.title')"
      :bordered="true"
    >
      <template #extra>
        <a-space wrap>
          <a-typography-text type="secondary">
            {{
              t('admin.jobsPage.metrics.updatedAt', {
                time: formatDate(operationsMetrics.generated_at),
              })
            }}
          </a-typography-text>
          <a-radio-group
            :model-value="operationsMetrics.range"
            type="button"
            size="small"
            :disabled="metricsLoading"
            data-testid="metrics-range"
            @change="selectMetricsRange"
          >
            <a-radio
              v-for="range in operationsMetrics.ranges"
              :key="range"
              :value="range"
            >
              {{ t(`admin.jobsPage.metrics.ranges.${range}`) }}
            </a-radio>
          </a-radio-group>
        </a-space>
      </template>

      <a-spin :loading="metricsLoading">
        <a-alert
          v-if="!operationsMetrics.available"
          :type="operationsMetrics.truncated ? 'warning' : 'error'"
          show-icon
          :title="t('admin.jobsPage.metrics.unavailableTitle')"
        >
          {{
            t(
              `admin.jobsPage.metrics.errors.${
                operationsMetrics.error_code || 'query_unavailable'
              }`,
            )
          }}
        </a-alert>

        <template v-else>
          <a-descriptions
            :column="{ xs: 2, sm: 2, xl: 4 }"
            layout="vertical"
            bordered
            size="small"
          >
            <a-descriptions-item :label="t('admin.jobsPage.metrics.requestLatency')">
              <a-space direction="vertical" :size="4" fill>
                <a-statistic
                  :value="operationsMetrics.summary.request_average_ms || 0"
                  :precision="2"
                  :suffix="t('admin.jobsPage.metrics.ms')"
                />
                <a-space wrap size="small">
                  <a-tag
                    :color="deltaColor(operationsMetrics.comparison.request_average_ms)"
                  >
                    {{ formatDelta(operationsMetrics.comparison.request_average_ms) }}
                  </a-tag>
                  <a-typography-text type="secondary">
                    {{
                      t('admin.jobsPage.metrics.sampleCount', {
                        count: operationsMetrics.summary.request_count || 0,
                      })
                    }}
                  </a-typography-text>
                </a-space>
              </a-space>
            </a-descriptions-item>

            <a-descriptions-item :label="t('admin.jobsPage.metrics.serverErrors')">
              <a-space direction="vertical" :size="4" fill>
                <a-statistic :value="operationsMetrics.summary.server_errors || 0" />
                <a-space wrap size="small">
                  <a-tag
                    :color="
                      (operationsMetrics.summary.request_error_rate_percent || 0) >=
                      operationsMetrics.thresholds.request_error_rate_percent
                        ? 'orange'
                        : 'green'
                    "
                  >
                    {{
                      t('admin.jobsPage.metrics.rateValue', {
                        value:
                          operationsMetrics.summary.request_error_rate_percent || 0,
                      })
                    }}
                  </a-tag>
                  <a-typography-text type="secondary">
                    {{
                      t('admin.jobsPage.metrics.thresholdValue', {
                        value:
                          operationsMetrics.thresholds
                            .request_error_rate_percent,
                      })
                    }}
                  </a-typography-text>
                </a-space>
              </a-space>
            </a-descriptions-item>

            <a-descriptions-item :label="t('admin.jobsPage.metrics.jobFailures')">
              <a-space direction="vertical" :size="4" fill>
                <a-statistic :value="operationsMetrics.summary.job_failures || 0" />
                <a-space wrap size="small">
                  <a-tag
                    :color="
                      (operationsMetrics.summary.job_failure_rate_percent || 0) >=
                      operationsMetrics.thresholds.job_failure_rate_percent
                        ? 'orange'
                        : 'green'
                    "
                  >
                    {{
                      t('admin.jobsPage.metrics.rateValue', {
                        value:
                          operationsMetrics.summary.job_failure_rate_percent || 0,
                      })
                    }}
                  </a-tag>
                  <a-typography-text type="secondary">
                    {{
                      t('admin.jobsPage.metrics.sampleCount', {
                        count: operationsMetrics.summary.job_count || 0,
                      })
                    }}
                  </a-typography-text>
                </a-space>
              </a-space>
            </a-descriptions-item>

            <a-descriptions-item :label="t('admin.jobsPage.metrics.queueUtilization')">
              <a-space direction="vertical" :size="4" fill>
                <a-statistic
                  :value="operationsMetrics.summary.queue_utilization_percent || 0"
                  :precision="1"
                  suffix="%"
                />
                <a-space wrap size="small">
                  <a-tag color="arcoblue">
                    {{
                      t('admin.jobsPage.metrics.queueBacklogValue', {
                        count: operationsMetrics.summary.queue_enqueued || 0,
                      })
                    }}
                  </a-tag>
                  <a-typography-text type="secondary">
                    {{
                      t('admin.jobsPage.metrics.workerCount', {
                        count: operationsMetrics.summary.queue_worker_count || 0,
                      })
                    }}
                  </a-typography-text>
                </a-space>
              </a-space>
            </a-descriptions-item>
          </a-descriptions>

          <a-divider />

          <a-grid :cols="{ xs: 1, xl: 5 }" :col-gap="16" :row-gap="16">
            <a-grid-item :span="{ xs: 1, xl: 2 }">
            <a-card
              :title="t('admin.jobsPage.metrics.thresholdsTitle')"
              :bordered="true"
            >
              <a-list :bordered="false" :split="true">
                <a-list-item
                  v-for="check in operationsMetrics.checks"
                  :key="check.key"
                >
                  <a-space direction="vertical" :size="8" fill>
                    <a-row align="center" justify="space-between">
                      <a-space wrap>
                        <a-tag :color="metricStatusColor(check.status)">
                          {{
                            t(
                              `admin.jobsPage.metrics.status.${check.status}`,
                            )
                          }}
                        </a-tag>
                        <a-typography-text>
                          {{
                            t(
                              `admin.jobsPage.metrics.checks.${check.key}`,
                            )
                          }}
                        </a-typography-text>
                      </a-space>
                      <a-typography-text type="secondary">
                        {{ formatCheckValue(check) }}
                      </a-typography-text>
                    </a-row>
                    <a-progress
                      :percent="check.percent"
                      :status="metricProgressStatus(check.status)"
                      size="small"
                      aria-hidden="true"
                    />
                  </a-space>
                </a-list-item>
              </a-list>
            </a-card>
            </a-grid-item>

            <a-grid-item :span="{ xs: 1, xl: 3 }">
            <a-card
              :title="t('admin.jobsPage.metrics.activityTitle')"
              :bordered="true"
            >
              <a-descriptions :column="{ xs: 1, sm: 2, md: 3 }" bordered size="small">
                <a-descriptions-item :label="t('admin.jobsPage.metrics.slowQueries')">
                  {{
                    t('admin.jobsPage.metrics.countWithMaximum', {
                      count: metricValue('slow_query_count'),
                      maximum: metricValue('slow_query_max_ms'),
                    })
                  }}
                </a-descriptions-item>
                <a-descriptions-item :label="t('admin.jobsPage.metrics.mail')">
                  {{
                    t('admin.jobsPage.metrics.failureFraction', {
                      failures: metricValue('mail_failures'),
                      total: metricValue('mail_deliveries'),
                    })
                  }}
                </a-descriptions-item>
                <a-descriptions-item :label="t('admin.jobsPage.metrics.paymentWebhooks')">
                  {{
                    t('admin.jobsPage.metrics.failureFraction', {
                      failures: metricValue('payment_webhook_failures'),
                      total: metricValue('payment_webhooks'),
                    })
                  }}
                </a-descriptions-item>
                <a-descriptions-item :label="t('admin.jobsPage.metrics.uploads')">
                  {{
                    t('admin.jobsPage.metrics.failureFraction', {
                      failures: metricValue('upload_failures'),
                      total: metricValue('uploads'),
                    })
                  }}
                </a-descriptions-item>
                <a-descriptions-item :label="t('admin.jobsPage.metrics.scans')">
                  {{
                    t('admin.jobsPage.metrics.failureFraction', {
                      failures: metricValue('scan_failures'),
                      total: metricValue('scans'),
                    })
                  }}
                </a-descriptions-item>
                <a-descriptions-item :label="t('admin.jobsPage.metrics.queryBudget')">
                  {{
                    t('admin.jobsPage.metrics.queryBudgetValue', {
                      count: operationsMetrics.row_count,
                      budget: operationsMetrics.row_budget,
                    })
                  }}
                </a-descriptions-item>
              </a-descriptions>
            </a-card>
            </a-grid-item>
          </a-grid>

          <a-divider />

          <a-table
            :data="operationsMetrics.series"
            :pagination="{ pageSize: 12, showTotal: true }"
            :bordered="{ cell: true }"
            :scroll="{ x: 980 }"
            stripe
            row-key="bucket_at"
          >
            <template #columns>
              <a-table-column
                data-index="bucket_at"
                :title="t('admin.jobsPage.metrics.period')"
                :width="190"
              >
                <template #cell="{ record }">
                  {{ formatDate(record.bucket_at) }}
                </template>
              </a-table-column>
              <a-table-column
                data-index="request_count"
                :title="t('admin.jobsPage.metrics.requests')"
              />
              <a-table-column
                data-index="request_average_ms"
                :title="t('admin.jobsPage.metrics.averageLatency')"
              >
                <template #cell="{ record }">
                  {{ record.request_average_ms }} {{ t('admin.jobsPage.metrics.ms') }}
                </template>
              </a-table-column>
              <a-table-column
                data-index="server_errors"
                :title="t('admin.jobsPage.metrics.serverErrorsShort')"
              />
              <a-table-column
                data-index="slow_queries"
                :title="t('admin.jobsPage.metrics.slowQueries')"
              />
              <a-table-column
                data-index="job_count"
                :title="t('admin.jobsPage.metrics.jobs')"
              />
              <a-table-column
                data-index="job_failures"
                :title="t('admin.jobsPage.metrics.jobFailuresShort')"
              />
              <a-table-column
                data-index="queue_enqueued"
                :title="t('admin.jobsPage.metrics.queueBacklog')"
              />
              <a-table-column
                data-index="queue_utilization_percent"
                :title="t('admin.jobsPage.metrics.queueUtilizationShort')"
              >
                <template #cell="{ record }">
                  {{ record.queue_utilization_percent }}%
                </template>
              </a-table-column>
            </template>
            <template #empty>
              <a-empty
                :description="t('admin.jobsPage.metrics.noSamples')"
                data-testid="metrics-empty-state"
              />
            </template>
          </a-table>
        </template>
      </a-spin>
    </a-card>
  </a-space>
</template>
