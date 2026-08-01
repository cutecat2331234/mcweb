<script setup lang="ts">
import { ref } from 'vue'
import { router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import HighRiskActionModal from '@/components/admin/HighRiskActionModal.vue'

defineOptions({ layout: AdminLayout })

type Fulfillment = {
  id: number
  delivery_id: string
  status: string
  status_label: string
  order_number: string
  product_name: string
  attempts_count: number
  max_attempts: number
  next_attempt_at?: string | null
  error_label?: string | null
  fulfilled_at?: string | null
  cancelled_at?: string | null
  cancel_reason?: string | null
  retryable: boolean
  cancellable: boolean
  exhausted: boolean
  target_server?: string | null
  target_server_process_state?: string | null
  target_server_url?: string | null
}

type Attempt = {
  id: number
  number: number
  action: string
  action_label: string
  trigger: string
  trigger_label: string
  status: string
  status_label: string
  error_label?: string | null
  reason?: string | null
  actor?: string | null
  started_at: string
  completed_at?: string | null
  next_retry_at?: string | null
}

const props = defineProps<{
  fulfillment: Fulfillment
  attempts: Attempt[]
  permissions: {
    retry: boolean
    cancel: boolean
  }
  paths: {
    index: string
    authorize: string
    execute: string
  }
}>()

const { t, locale } = useI18n()
const action = ref<'retry' | 'cancel' | null>(null)

function statusColor(status: string) {
  if (status === 'fulfilled' || status === 'succeeded') return 'green'
  if (status === 'failed') return 'red'
  if (status === 'cancelled') return 'gray'
  if (status === 'processing') return 'arcoblue'
  return 'orange'
}

function formatDate(value?: string | null) {
  if (!value) return t('admin.fulfillments.notScheduled')
  return new Intl.DateTimeFormat(locale.value, {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(value))
}

function completed() {
  action.value = null
  router.reload({
    only: ['fulfillment', 'attempts', 'permissions'],
    preserveScroll: true,
  })
}

function visitTargetServer() {
  const url = props.fulfillment.target_server_url
  if (url) router.visit(url)
}

</script>

<template>
  <a-space direction="vertical" :size="16" fill>
    <a-page-header
      :title="t('admin.fulfillments.title', { id: fulfillment.delivery_id })"
      :subtitle="t('admin.fulfillments.detailSubtitle')"
      :show-back="false"
    >
      <template #extra>
        <a-space wrap>
          <a-button
            v-if="permissions.retry && fulfillment.retryable"
            type="primary"
            status="warning"
            @click="action = 'retry'"
          >
            {{ t('admin.fulfillments.retry') }}
          </a-button>
          <a-button
            v-if="permissions.cancel && fulfillment.cancellable"
            status="danger"
            @click="action = 'cancel'"
          >
            {{ t('admin.fulfillments.cancel') }}
          </a-button>
          <a-button @click="router.visit(paths.index)">
            {{ t('admin.ui.back') }}
          </a-button>
        </a-space>
      </template>
    </a-page-header>

    <a-row justify="center">
      <a-col :xs="24" :md="22" :lg="20" :xl="18">
        <a-space direction="vertical" :size="16" fill>
          <a-alert
            v-if="fulfillment.exhausted"
            type="error"
            show-icon
            :title="t('admin.fulfillments.exhaustedTitle')"
          >
            {{ t('admin.fulfillments.exhaustedDescription') }}
          </a-alert>
          <a-alert
            v-else-if="fulfillment.error_label"
            type="warning"
            show-icon
            :title="t('admin.fulfillments.failureTitle')"
          >
            {{ fulfillment.error_label }}
          </a-alert>

          <a-grid :cols="{ xs: 1, md: 3 }" :col-gap="16" :row-gap="16">
            <a-grid-item>
              <a-card size="small" :bordered="true">
                <a-statistic
                  :title="t('admin.common.status')"
                  :value="fulfillment.status_label"
                >
                  <template #suffix>
                    <a-tag :color="statusColor(fulfillment.status)">
                      {{ fulfillment.status_label }}
                    </a-tag>
                  </template>
                </a-statistic>
              </a-card>
            </a-grid-item>
            <a-grid-item>
              <a-card size="small" :bordered="true">
                <a-space direction="vertical" :size="12" fill>
                  <a-statistic
                    :title="t('admin.fulfillments.attempts')"
                    :value="fulfillment.attempts_count"
                    :suffix="'/ ' + fulfillment.max_attempts"
                  />
                  <a-progress
                    :percent="Math.min(1, fulfillment.attempts_count / fulfillment.max_attempts)"
                    :show-text="false"
                    :status="fulfillment.exhausted ? 'danger' : 'normal'"
                  />
                </a-space>
              </a-card>
            </a-grid-item>
            <a-grid-item>
              <a-card size="small" :bordered="true">
                <a-statistic
                  :title="t('admin.fulfillments.nextAttempt')"
                  :value="formatDate(fulfillment.next_attempt_at)"
                />
              </a-card>
            </a-grid-item>
          </a-grid>

          <a-card
            size="small"
            :title="t('admin.fulfillments.contextTitle')"
            :bordered="true"
          >
            <a-descriptions :column="{ xs: 1, md: 2 }" bordered>
              <a-descriptions-item :label="t('admin.fulfillments.columns.delivery')">
                {{ fulfillment.delivery_id }}
              </a-descriptions-item>
              <a-descriptions-item :label="t('admin.common.order')">
                {{ fulfillment.order_number }}
              </a-descriptions-item>
              <a-descriptions-item :label="t('admin.common.product')">
                {{ fulfillment.product_name }}
              </a-descriptions-item>
              <a-descriptions-item :label="t('admin.fulfillments.targetServer')">
                <a-link
                  v-if="fulfillment.target_server_url"
                  :href="fulfillment.target_server_url"
                  @click.prevent="visitTargetServer"
                >
                  {{ fulfillment.target_server }}
                </a-link>
                <a-typography-text v-else type="secondary">
                  {{ fulfillment.target_server || t('admin.fulfillments.notConfigured') }}
                </a-typography-text>
              </a-descriptions-item>
              <a-descriptions-item
                v-if="fulfillment.target_server"
                :label="t('admin.fulfillments.targetServerState')"
              >
                {{ fulfillment.target_server_process_state || t('admin.fulfillments.unknownState') }}
              </a-descriptions-item>
              <a-descriptions-item
                v-if="fulfillment.cancel_reason"
                :label="t('admin.fulfillments.cancelReason')"
              >
                {{ fulfillment.cancel_reason }}
              </a-descriptions-item>
            </a-descriptions>
          </a-card>

          <a-card
            size="small"
            :title="t('admin.fulfillments.timelineTitle')"
            :bordered="true"
          >
            <a-empty
              v-if="attempts.length === 0"
              :description="t('admin.fulfillments.noAttempts')"
            />
            <a-timeline v-else>
              <a-timeline-item
                v-for="attempt in attempts"
                :key="attempt.id"
                :dot-color="statusColor(attempt.status)"
              >
                <a-space direction="vertical" size="mini">
                  <a-space wrap>
                    <a-typography-text bold>
                      {{ t('admin.fulfillments.attemptTitle', { number: attempt.number }) }}
                    </a-typography-text>
                    <a-tag :color="statusColor(attempt.status)">
                      {{ attempt.status_label }}
                    </a-tag>
                    <a-tag bordered>{{ attempt.action_label }}</a-tag>
                    <a-tag bordered>{{ attempt.trigger_label }}</a-tag>
                  </a-space>
                  <a-typography-text type="secondary">
                    {{ formatDate(attempt.started_at) }}
                    <template v-if="attempt.actor"> · {{ attempt.actor }}</template>
                  </a-typography-text>
                  <a-typography-text v-if="attempt.error_label" type="danger">
                    {{ attempt.error_label }}
                  </a-typography-text>
                  <a-typography-text v-if="attempt.reason">
                    {{ t('admin.fulfillments.reasonLabel', { reason: attempt.reason }) }}
                  </a-typography-text>
                  <a-typography-text v-if="attempt.next_retry_at" type="warning">
                    {{ t('admin.fulfillments.retryScheduled', {
                      time: formatDate(attempt.next_retry_at),
                    }) }}
                  </a-typography-text>
                </a-space>
              </a-timeline-item>
            </a-timeline>
          </a-card>
        </a-space>
      </a-col>
    </a-row>

    <HighRiskActionModal
      :visible="action !== null"
      :title="action === 'cancel'
        ? t('admin.fulfillments.cancelTitle')
        : t('admin.fulfillments.retryTitle')"
      :authorization-url="paths.authorize"
      :action-url="paths.execute"
      :payload="{ fulfillment_action: { action } }"
      @update:visible="(visible) => { if (!visible) action = null }"
      @completed="completed"
    />
  </a-space>
</template>
