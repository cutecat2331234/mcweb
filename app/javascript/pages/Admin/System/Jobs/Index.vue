<script setup lang="ts">
import { reactive, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { router } from '@inertiajs/vue3'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { adminRoutes } from '@/lib/adminRoutes'

defineOptions({ layout: AdminLayout })

const { t, te, locale } = useI18n()
const metricsLoading = ref(false)
const manualTaskLoading = ref<string | null>(null)
const manualTaskArguments = reactive<Record<string, string | number | undefined>>({})

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
  metricsUrl: string
  developerMode: {
    enabled: boolean
    profile?: string | null
  }
  automaticRegistration: boolean
  manualTaskRunUrl: string
  manualTasks: Array<{
    key: string
    labelKey: string
    descriptionKey: string
    arguments: Array<{
      key: string
      type: 'integer' | 'integer_list' | 'string' | 'uuid_list'
      required: boolean
      minimum?: number
      maximum?: number
      maximumItems?: number
      labelKey?: string
      helpKey?: string
    }>
  }>
  manualTaskRuns: Array<{
    id: number
    taskKey: string
    status: 'queued' | 'running' | 'succeeded' | 'failed'
    requestedBy?: string | null
    requestedAt?: string | null
    startedAt?: string | null
    finishedAt?: string | null
    errorCode?: string | null
  }>
  securityRecoveryDeliveries: Array<{
    publicId: string
    userId: number
    purpose: 'password_reset' | 'totp_recovery'
    status: 'pending' | 'sent' | 'failed'
    durableStatus: string
    retryable: boolean
    attemptCount: number
    requestedAt?: string | null
    lastEventAt?: string | null
    reasonCode?: string | null
  }>
  securityRecoveryCopy: {
    title: string
    description: string
    empty: string
    intentId: string
    userId: string
    purpose: string
    status: string
    attempts: string
    requestedAt: string
    lastEventAt: string
    reason: string
    retry: string
    retryable: string
    terminal: string
    purposes: Record<'password_reset' | 'totp_recovery', string>
    statuses: Record<'pending' | 'sent' | 'failed', string>
  }
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
  redisRecovery: {
    dependency: 'sidekiq_redis'
    status: 'healthy' | 'recovering' | 'warning' | 'unavailable' | 'error' | 'local'
    redis_available?: boolean | null
    queue_status: string
    database_fallback: boolean
    ledger_available: boolean
    ledger_error_code?: string
    pending_intents: number
    running_intents: number
    retrying_intents: number
    dead_lettered_intents: number
    oldest_pending_at?: string | null
    oldest_pending_seconds?: number | null
    last_enqueue_failure_at?: string | null
    last_recovery_handoff_at?: string | null
    last_recovery_failure_at?: string | null
    last_recovery_result: 'accepted' | 'failed' | 'none'
    last_recovery_trigger?: 'maintenance' | 'manual' | null
    generated_at: string
  }
  redisRecoveryCopy: {
    title: string
    description: string
    redis: string
    ledger: string
    pending: string
    retrying: string
    deadLettered: string
    oldestPending: string
    lastEnqueueFailure: string
    lastRecoveryHandoff: string
    lastRecoveryFailure: string
    recoveryResult: string
    fallbackActive: string
    handoffNote: string
    statuses: Record<string, string>
    availability: Record<'available' | 'unavailable' | 'notApplicable', string>
    results: Record<'accepted' | 'failed' | 'none', string>
    triggers: Record<'maintenance' | 'manual', string>
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

function manualTaskArgumentPresent(argument: (typeof props.manualTasks)[number]['arguments'][number]) {
  const value = manualTaskArguments[argument.key]
  return value !== undefined && value !== null && String(value).trim().length > 0
}

function manualTaskArgumentLabel(argument: (typeof props.manualTasks)[number]['arguments'][number]) {
  if (argument.labelKey && te(argument.labelKey)) return t(argument.labelKey)
  return argument.key.replaceAll('_', ' ')
}

function manualTaskArgumentHelp(argument: (typeof props.manualTasks)[number]['arguments'][number]) {
  if (argument.helpKey && te(argument.helpKey)) return t(argument.helpKey)

  const key = argument.type === 'integer'
    ? 'admin.jobsPage.manualTasks.integerHelp'
    : 'admin.jobsPage.manualTasks.integerListHelp'
  return t(key, {
    minimum: argument.minimum ?? 0,
    maximum: argument.maximumItems ?? '∞',
  })
}

function manualTaskDisabled(task: (typeof props.manualTasks)[number]) {
  return manualTaskLoading.value !== null
    || task.arguments.some((argument) => argument.required && !manualTaskArgumentPresent(argument))
}

function runManualTask(task: (typeof props.manualTasks)[number]) {
  if (manualTaskDisabled(task)) return

  const argumentsPayload = task.arguments.reduce<Record<string, string | number>>((payload, argument) => {
    const value = manualTaskArguments[argument.key]
    if (manualTaskArgumentPresent(argument) && value !== undefined) payload[argument.key] = value
    return payload
  }, {})

  router.post(props.manualTaskRunUrl, { task_key: task.key, arguments: argumentsPayload }, {
    preserveScroll: true,
    onStart: () => {
      manualTaskLoading.value = task.key
    },
    onFinish: () => {
      manualTaskLoading.value = null
    },
  })
}

function manualTaskLabel(taskKey: string) {
  const task = props.manualTasks.find((candidate) => candidate.key === taskKey)
  return task ? t(task.labelKey) : taskKey
}

function manualTaskStatusColor(status: string) {
  if (status === 'succeeded') return 'green'
  if (status === 'failed') return 'red'
  if (status === 'running') return 'arcoblue'
  return 'orange'
}

function securityRecoveryStatusColor(status: string) {
  if (status === 'sent') return 'green'
  if (status === 'failed') return 'red'
  return 'orange'
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
            <a-button type="primary" :href="adminRoutes.sidekiq" long>
              {{ t('admin.jobsPage.openDashboard') }}
            </a-button>
          </a-space>
        </a-card>
      </a-grid-item>
    </a-grid>

    <a-card :title="t('admin.jobsPage.manualTasks.title')" :bordered="true">
      <a-space direction="vertical" :size="16" fill>
        <a-alert type="info" show-icon>
          {{ t('admin.jobsPage.manualTasks.description') }}
        </a-alert>

        <a-grid
          v-if="manualTasks.length > 0"
          :cols="{ xs: 1, md: 2 }"
          :col-gap="12"
          :row-gap="12"
        >
          <a-grid-item v-for="task in manualTasks" :key="task.key">
            <a-card size="small" :bordered="true">
              <a-space direction="vertical" :size="10" fill>
                <a-typography-title :heading="6">
                  {{ t(task.labelKey) }}
                </a-typography-title>
                <a-typography-paragraph type="secondary">
                  {{ t(task.descriptionKey) }}
                </a-typography-paragraph>
                <a-form-item
                  v-for="argument in task.arguments"
                  :key="argument.key"
                  :label="manualTaskArgumentLabel(argument)"
                  :help="manualTaskArgumentHelp(argument)"
                  :required="argument.required"
                >
                  <a-input-number
                    v-if="argument.type === 'integer'"
                    v-model="manualTaskArguments[argument.key]"
                    :min="argument.minimum"
                    :precision="0"
                    allow-clear
                  />
                  <a-input
                    v-else
                    v-model="manualTaskArguments[argument.key]"
                    allow-clear
                  />
                </a-form-item>
                <a-button
                  type="primary"
                  long
                  :disabled="manualTaskDisabled(task)"
                  :loading="manualTaskLoading === task.key"
                  @click="runManualTask(task)"
                >
                  {{ t('admin.jobsPage.manualTasks.run') }}
                </a-button>
              </a-space>
            </a-card>
          </a-grid-item>
        </a-grid>
        <a-empty v-else :description="t('admin.jobsPage.manualTasks.noTasks')" />

        <a-divider />

        <a-typography-title :heading="6">
          {{ t('admin.jobsPage.manualTasks.recentRuns') }}
        </a-typography-title>
        <a-table
          v-if="manualTaskRuns.length > 0"
          :data="manualTaskRuns"
          :pagination="false"
          row-key="id"
          :scroll="{ x: 760 }"
        >
          <template #columns>
            <a-table-column :title="t('admin.jobsPage.manualTasks.task')">
              <template #cell="{ record }">
                {{ manualTaskLabel(record.taskKey) }}
              </template>
            </a-table-column>
            <a-table-column :title="t('admin.jobsPage.manualTasks.status')" :width="120">
              <template #cell="{ record }">
                <a-tag :color="manualTaskStatusColor(record.status)">
                  {{ t(`admin.jobsPage.manualTasks.statuses.${record.status}`) }}
                </a-tag>
              </template>
            </a-table-column>
            <a-table-column
              data-index="requestedBy"
              :title="t('admin.jobsPage.manualTasks.requestedBy')"
              :width="160"
            />
            <a-table-column :title="t('admin.jobsPage.manualTasks.requestedAt')" :width="190">
              <template #cell="{ record }">{{ formatDate(record.requestedAt) }}</template>
            </a-table-column>
            <a-table-column :title="t('admin.jobsPage.manualTasks.finishedAt')" :width="190">
              <template #cell="{ record }">{{ formatDate(record.finishedAt) }}</template>
            </a-table-column>
            <a-table-column :title="t('admin.jobsPage.manualTasks.result')" :width="260">
              <template #cell="{ record }">
                <a-space wrap size="small">
                  <a-tag v-if="record.result.partial" color="orange">
                    {{ t('admin.jobsPage.manualTasks.partial') }}
                  </a-tag>
                  <a-tag>
                    {{
                      t('admin.jobsPage.manualTasks.processedCount', {
                        count: record.result.processed_count,
                      })
                    }}
                  </a-tag>
                  <a-tag :color="record.result.failed_count ? 'red' : 'green'">
                    {{
                      t('admin.jobsPage.manualTasks.failedCount', {
                        count: record.result.failed_count,
                      })
                    }}
                  </a-tag>
                  <a-tag v-if="record.result.error_codes_count" color="orange">
                    {{
                      t('admin.jobsPage.manualTasks.errorCodesCount', {
                        count: record.result.error_codes_count,
                      })
                    }}
                  </a-tag>
                </a-space>
              </template>
            </a-table-column>
            <a-table-column :title="t('admin.jobsPage.manualTasks.errorCode')" :width="190">
              <template #cell="{ record }">{{ record.errorCode || t('common.notAvailable') }}</template>
            </a-table-column>
          </template>
        </a-table>
        <a-empty v-else :description="t('admin.jobsPage.manualTasks.noRuns')" />
      </a-space>
    </a-card>

    <a-card
      :title="securityRecoveryCopy.title"
      :bordered="true"
      data-testid="security-recovery-deliveries"
    >
      <a-space direction="vertical" :size="12" fill>
        <a-alert type="info" show-icon>
          {{ securityRecoveryCopy.description }}
        </a-alert>
        <a-table
          v-if="securityRecoveryDeliveries.length > 0"
          :data="securityRecoveryDeliveries"
          :pagination="false"
          row-key="publicId"
          :scroll="{ x: 1480 }"
        >
          <template #columns>
            <a-table-column :title="securityRecoveryCopy.intentId" :width="315">
              <template #cell="{ record }">
                <a-typography-text code copyable>
                  {{ record.publicId }}
                </a-typography-text>
              </template>
            </a-table-column>
            <a-table-column
              data-index="userId"
              :title="securityRecoveryCopy.userId"
              :width="100"
            />
            <a-table-column :title="securityRecoveryCopy.purpose" :width="160">
              <template #cell="{ record }">
                {{ securityRecoveryCopy.purposes[record.purpose] }}
              </template>
            </a-table-column>
            <a-table-column :title="securityRecoveryCopy.status" :width="130">
              <template #cell="{ record }">
                <a-tooltip :content="record.durableStatus">
                  <a-tag :color="securityRecoveryStatusColor(record.status)">
                    {{ securityRecoveryCopy.statuses[record.status] }}
                  </a-tag>
                </a-tooltip>
              </template>
            </a-table-column>
            <a-table-column
              data-index="attemptCount"
              :title="securityRecoveryCopy.attempts"
              :width="100"
            />
            <a-table-column :title="securityRecoveryCopy.requestedAt" :width="190">
              <template #cell="{ record }">
                {{ formatDate(record.requestedAt) }}
              </template>
            </a-table-column>
            <a-table-column :title="securityRecoveryCopy.lastEventAt" :width="190">
              <template #cell="{ record }">
                {{ formatDate(record.lastEventAt) }}
              </template>
            </a-table-column>
            <a-table-column :title="securityRecoveryCopy.reason" :width="190">
              <template #cell="{ record }">
                {{ record.reasonCode || t('common.notAvailable') }}
              </template>
            </a-table-column>
            <a-table-column :title="securityRecoveryCopy.retry" :width="150">
              <template #cell="{ record }">
                <a-tag :color="record.retryable ? 'orange' : 'gray'">
                  {{
                    record.retryable
                      ? securityRecoveryCopy.retryable
                      : securityRecoveryCopy.terminal
                  }}
                </a-tag>
              </template>
            </a-table-column>
          </template>
        </a-table>
        <a-empty v-else :description="securityRecoveryCopy.empty" />
      </a-space>
    </a-card>

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

      <a-space direction="vertical" :size="12" fill data-testid="redis-recovery-snapshot">
        <div>
          <a-typography-title :heading="6">
            {{ redisRecoveryCopy.title }}
          </a-typography-title>
          <a-typography-paragraph type="secondary">
            {{ redisRecoveryCopy.description }}
          </a-typography-paragraph>
        </div>

        <a-alert
          v-if="redisRecovery.database_fallback"
          type="warning"
          show-icon
          :title="redisRecoveryCopy.fallbackActive"
        />

        <a-descriptions
          :column="{ xs: 1, sm: 2, xl: 4 }"
          layout="vertical"
          bordered
          size="small"
        >
          <a-descriptions-item :label="redisRecoveryCopy.redis">
            <a-tag
              :color="
                redisRecovery.redis_available === null
                  ? 'gray'
                  : redisRecovery.redis_available
                    ? 'green'
                    : 'red'
              "
            >
              {{
                redisRecoveryCopy.availability[
                  redisRecovery.redis_available === null
                    ? 'notApplicable'
                    : redisRecovery.redis_available
                      ? 'available'
                      : 'unavailable'
                ]
              }}
            </a-tag>
          </a-descriptions-item>
          <a-descriptions-item :label="redisRecoveryCopy.ledger">
            <a-space wrap>
              <a-tag :color="redisRecovery.ledger_available ? 'green' : 'red'">
                {{
                  redisRecoveryCopy.availability[
                    redisRecovery.ledger_available ? 'available' : 'unavailable'
                  ]
                }}
              </a-tag>
              <a-tag :color="queueStatusColor(redisRecovery.status)">
                {{ redisRecoveryCopy.statuses[redisRecovery.status] }}
              </a-tag>
            </a-space>
          </a-descriptions-item>
          <a-descriptions-item :label="redisRecoveryCopy.pending">
            <a-statistic :value="redisRecovery.pending_intents" />
          </a-descriptions-item>
          <a-descriptions-item :label="redisRecoveryCopy.retrying">
            <a-statistic :value="redisRecovery.retrying_intents" />
          </a-descriptions-item>
          <a-descriptions-item :label="redisRecoveryCopy.deadLettered">
            <a-statistic :value="redisRecovery.dead_lettered_intents" />
          </a-descriptions-item>
          <a-descriptions-item :label="redisRecoveryCopy.oldestPending">
            {{ formatDate(redisRecovery.oldest_pending_at) }}
          </a-descriptions-item>
          <a-descriptions-item :label="redisRecoveryCopy.lastEnqueueFailure">
            {{ formatDate(redisRecovery.last_enqueue_failure_at) }}
          </a-descriptions-item>
          <a-descriptions-item :label="redisRecoveryCopy.lastRecoveryHandoff">
            <a-space direction="vertical" :size="4" fill>
              <span>{{ formatDate(redisRecovery.last_recovery_handoff_at) }}</span>
              <a-tag v-if="redisRecovery.last_recovery_trigger" color="arcoblue">
                {{ redisRecoveryCopy.triggers[redisRecovery.last_recovery_trigger] }}
              </a-tag>
            </a-space>
          </a-descriptions-item>
          <a-descriptions-item :label="redisRecoveryCopy.lastRecoveryFailure">
            {{ formatDate(redisRecovery.last_recovery_failure_at) }}
          </a-descriptions-item>
          <a-descriptions-item :label="redisRecoveryCopy.recoveryResult">
            <a-tag
              :color="
                redisRecovery.last_recovery_result === 'failed'
                  ? 'red'
                  : redisRecovery.last_recovery_result === 'none'
                    ? 'gray'
                    : 'green'
              "
            >
              {{ redisRecoveryCopy.results[redisRecovery.last_recovery_result] }}
            </a-tag>
          </a-descriptions-item>
        </a-descriptions>

        <a-typography-text type="secondary">
          {{ redisRecoveryCopy.handoffNote }}
        </a-typography-text>
      </a-space>

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
