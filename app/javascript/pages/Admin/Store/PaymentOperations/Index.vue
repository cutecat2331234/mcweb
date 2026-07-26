<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { Link, router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import {
  Alert,
  Button,
  Card,
  Empty,
  InputSearch,
  Modal,
  Option,
  PageHeader,
  Pagination,
  Select,
  Space,
  Statistic,
  Table,
  TableColumn,
  TabPane,
  Tabs,
  Tag,
  Textarea,
  TypographyText,
} from '@mcweb/ui'
import ArcoAdminLayout from '@/layouts/ArcoAdminLayout.vue'
import { adminRoutes } from '@/lib/adminRoutes'

defineOptions({ layout: ArcoAdminLayout })

type ViewName = 'payments' | 'webhooks' | 'orphans' | 'refunds'

type SummaryBucket = {
  total: number
  failed?: number
  processing?: number
  stale?: number
  retry_scheduled?: number
  dead_letter?: number
}

type OperationRow = {
  id: number
  order_id?: string
  order_number?: string
  payment_record_id?: number
  provider: string
  provider_reference?: string | null
  event_reference?: string | null
  event_type?: string
  status: string
  provider_status?: string | null
  provider_error_code?: string | null
  amount_cents?: number
  currency?: string
  orphaned?: boolean
  orphan_reason?: string | null
  stale?: boolean
  error_recorded?: boolean
  last_error_code?: string | null
  attempt_count?: number
  retry_count?: number
  manual_replay_count?: number
  next_retry_at?: string | null
  last_attempted_at?: string | null
  dead_lettered_at?: string | null
  replay?: {
    url: string
    token: string
  }
  processing_started_at?: string | null
  created_at: string
  updated_at: string
  processed_at?: string | null
}

type ProviderStatus = {
  provider: string
  configured: boolean
  enabled: boolean
  checkout_ready: boolean
  payment_counts: Record<string, number>
  refund_counts: Record<string, number>
  updated_at: string | null
}

type PaginationMeta = {
  page: number
  pages: number
  count: number
  from: number | null
  to: number | null
}

const props = defineProps<{
  view: ViewName
  filters: {
    provider: string | null
    status: string | null
    provider_status: string | null
    q: string | null
  }
  filterOptions: {
    providers: string[]
    statuses: string[]
    provider_statuses: string[]
  }
  summary: Record<ViewName, SummaryBucket>
  providerStatuses: ProviderStatus[]
  rows: OperationRow[]
  pagination: PaginationMeta
  replayEnabled: boolean
}>()

const { locale, t, te } = useI18n()
const provider = ref(props.filters.provider || '')
const status = ref(props.filters.status || '')
const providerStatus = ref(props.filters.provider_status || '')
const query = ref(props.filters.q || '')
const replayEvent = ref<OperationRow | null>(null)
const replayReason = ref('')
const replaySubmitting = ref(false)
const replayVisible = computed({
  get: () => replayEvent.value !== null,
  set: (visible: boolean) => {
    if (!visible) closeReplay()
  },
})

watch(
  () => props.filters,
  (filters) => {
    provider.value = filters.provider || ''
    status.value = filters.status || ''
    providerStatus.value = filters.provider_status || ''
    query.value = filters.q || ''
  },
)

const currentSummary = computed(() => props.summary[props.view])
const viewKeys: ViewName[] = ['payments', 'webhooks', 'orphans', 'refunds']

function viewLabel(view: ViewName) {
  return t(`admin.paymentOperations.${view}`)
}

function statusLabel(value: string | null | undefined) {
  if (!value) return '—'
  const key = `admin.paymentOperations.statuses.${value}`
  return te(key) ? t(key) : value
}

function statusColor(value: string | null | undefined) {
  switch (value) {
    case 'succeeded':
    case 'processed':
    case 'completed':
      return 'green'
    case 'failed':
    case 'dead_letter':
    case 'rejected':
    case 'cancelled':
      return 'red'
    case 'processing':
    case 'received':
    case 'pending':
    case 'approved':
      return 'orange'
    case 'stale':
      return 'magenta'
    default:
      return 'arcoblue'
  }
}

function formatMoney(row: OperationRow) {
  if (row.amount_cents === undefined || !row.currency) return '—'
  try {
    return new Intl.NumberFormat(locale.value, {
      style: 'currency',
      currency: row.currency,
    }).format(row.amount_cents / 100)
  } catch {
    return `${row.amount_cents / 100} ${row.currency}`
  }
}

function formatTime(value: string | null | undefined) {
  if (!value) return '—'
  return new Intl.DateTimeFormat(locale.value, {
    dateStyle: 'short',
    timeStyle: 'medium',
  }).format(new Date(value))
}

function formatCounts(counts: Record<string, number>) {
  const entries = Object.entries(counts)
  if (!entries.length) return t('admin.paymentOperations.noCounts')
  return entries
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([key, count]) => `${statusLabel(key)} ${count}`)
    .join(' · ')
}

function visit(patch: Record<string, string | number | undefined>) {
  const next: Record<string, string | number> = {
    view: props.view,
    ...(provider.value ? { provider: provider.value } : {}),
    ...(status.value ? { status: status.value } : {}),
    ...(providerStatus.value ? { provider_status: providerStatus.value } : {}),
    ...(query.value ? { q: query.value } : {}),
  }

  Object.entries(patch).forEach(([key, value]) => {
    if (value === undefined || value === '') delete next[key]
    else next[key] = value
  })

  router.get(adminRoutes.storePaymentOperations, next, {
    preserveScroll: true,
    preserveState: true,
    replace: true,
  })
}

function changeView(value: string | number) {
  visit({
    view: String(value),
    status: undefined,
    provider_status: undefined,
  })
}

function visitPage(page: number) {
  visit({ page })
}

function openReplay(event: OperationRow) {
  if (!event.replay) return
  replayReason.value = ''
  replayEvent.value = event
}

function closeReplay() {
  if (replaySubmitting.value) return
  replayEvent.value = null
  replayReason.value = ''
}

function submitReplay() {
  const event = replayEvent.value
  const reason = replayReason.value.trim()
  if (!event?.replay || reason.length < 10 || reason.length > 500) return

  router.post(
    event.replay.url,
    {
      token: event.replay.token,
      reason,
    },
    {
      preserveScroll: true,
      onStart: () => {
        replaySubmitting.value = true
      },
      onSuccess: () => {
        replayEvent.value = null
        replayReason.value = ''
      },
      onFinish: () => {
        replaySubmitting.value = false
      },
    },
  )
}
</script>

<template>
  <section>
    <PageHeader
      :title="t('admin.paymentOperations.title')"
      :subtitle="t('admin.paymentOperations.subtitle')"
      :show-back="false"
      class="mb-4 !px-0"
    />

    <Alert
      type="info"
      show-icon
      :closable="false"
      :title="replayEnabled
        ? t('admin.paymentOperations.replayNotice')
        : t('admin.paymentOperations.readOnlyNotice')"
      class="mb-4"
    />

    <div class="mb-4 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
      <Card
        v-for="key in viewKeys"
        :key="key"
        :bordered="false"
        size="small"
        class="bg-[var(--color-fill-1)]"
      >
        <Statistic :title="viewLabel(key)" :value="summary[key].total" />
      </Card>
    </div>

    <Card
      :title="t('admin.paymentOperations.providerHealth')"
      :bordered="false"
      class="mb-4 bg-[var(--color-fill-1)]"
    >
      <div v-if="providerStatuses.length" class="grid gap-3 lg:grid-cols-2 2xl:grid-cols-3">
        <Card
          v-for="item in providerStatuses"
          :key="item.provider"
          :title="item.provider"
          size="small"
          :bordered="false"
          class="bg-[var(--color-bg-2)]"
        >
          <Space wrap class="mb-3">
            <Tag :color="item.configured ? 'blue' : 'gray'">
              {{ item.configured ? t('admin.paymentOperations.configured') : t('admin.paymentOperations.missingConfig') }}
            </Tag>
            <Tag :color="item.enabled ? 'green' : 'gray'">
              {{ item.enabled ? t('admin.paymentOperations.enabled') : t('admin.paymentOperations.disabled') }}
            </Tag>
            <Tag :color="item.checkout_ready ? 'green' : 'orange'">
              {{ item.checkout_ready ? t('admin.paymentOperations.ready') : t('admin.paymentOperations.notReady') }}
            </Tag>
          </Space>
          <div class="space-y-1 text-sm text-[var(--color-text-2)]">
            <p>{{ t('admin.paymentOperations.paymentCounts', { counts: formatCounts(item.payment_counts) }) }}</p>
            <p>{{ t('admin.paymentOperations.refundCounts', { counts: formatCounts(item.refund_counts) }) }}</p>
          </div>
        </Card>
      </div>
      <Empty v-else />
    </Card>

    <Card :bordered="false">
      <Tabs :active-key="view" type="rounded" @change="changeView">
        <TabPane
          v-for="key in viewKeys"
          :key="key"
          :title="`${viewLabel(key)} (${summary[key].total})`"
        />
      </Tabs>

      <div class="mb-4 flex flex-wrap items-center gap-3">
        <Select
          v-model="provider"
          allow-clear
          :placeholder="t('admin.paymentOperations.allProviders')"
          class="w-full sm:w-44"
          @change="visit({ provider: provider || undefined })"
          @clear="visit({ provider: undefined })"
        >
          <Option v-for="item in filterOptions.providers" :key="item" :value="item">
            {{ item }}
          </Option>
        </Select>

        <Select
          v-model="status"
          allow-clear
          :placeholder="t('admin.paymentOperations.allStatuses')"
          class="w-full sm:w-44"
          @change="visit({ status: status || undefined })"
          @clear="visit({ status: undefined })"
        >
          <Option v-for="item in filterOptions.statuses" :key="item" :value="item">
            {{ statusLabel(item) }}
          </Option>
        </Select>

        <Select
          v-if="view === 'refunds'"
          v-model="providerStatus"
          allow-clear
          :placeholder="t('admin.paymentOperations.allProviderStatuses')"
          class="w-full sm:w-52"
          @change="visit({ provider_status: providerStatus || undefined })"
          @clear="visit({ provider_status: undefined })"
        >
          <Option v-for="item in filterOptions.provider_statuses" :key="item" :value="item">
            {{ item }}
          </Option>
        </Select>

        <InputSearch
          v-model="query"
          allow-clear
          search-button
          :placeholder="t('admin.paymentOperations.searchPlaceholder')"
          class="min-w-0 flex-1 basis-full sm:min-w-64 sm:basis-64"
          @search="visit({ q: query || undefined })"
          @clear="visit({ q: undefined })"
        />
      </div>

      <div class="mb-4 flex flex-wrap gap-2">
        <Tag color="blue">{{ t('admin.paymentOperations.total') }}: {{ currentSummary.total }}</Tag>
        <Tag v-if="currentSummary.failed !== undefined" color="red">
          {{ t('admin.paymentOperations.failed') }}: {{ currentSummary.failed }}
        </Tag>
        <Tag v-if="currentSummary.processing !== undefined" color="orange">
          {{ t('admin.paymentOperations.processing') }}: {{ currentSummary.processing }}
        </Tag>
        <Tag v-if="currentSummary.stale !== undefined" color="magenta">
          {{ t('admin.paymentOperations.stale') }}: {{ currentSummary.stale }}
        </Tag>
        <Tag v-if="currentSummary.retry_scheduled !== undefined" color="orange">
          {{ t('admin.paymentOperations.retryScheduled') }}: {{ currentSummary.retry_scheduled }}
        </Tag>
        <Tag v-if="currentSummary.dead_letter !== undefined" color="red">
          {{ t('admin.paymentOperations.deadLetter') }}: {{ currentSummary.dead_letter }}
        </Tag>
      </div>

      <div class="overflow-x-auto">
        <Table
          :data="rows"
          :pagination="false"
          row-key="id"
          :bordered="{ wrapper: true, cell: false }"
          :scroll="{ x: 1380 }"
          stripe
        >
          <template #columns>
            <template v-if="view === 'payments' || view === 'orphans'">
              <TableColumn :title="t('admin.paymentOperations.order')" data-index="order_number" :width="170">
                <template #cell="{ record }">
                  <Link
                    :href="adminRoutes.storeOrder(record.order_id)"
                    class="arco-link font-medium no-underline"
                  >
                    {{ record.order_number }}
                  </Link>
                </template>
              </TableColumn>
              <TableColumn :title="t('admin.paymentOperations.provider')" data-index="provider" :width="120" />
              <TableColumn
                :title="t('admin.paymentOperations.reference')"
                data-index="provider_reference"
                :width="170"
                ellipsis
                tooltip
              />
              <TableColumn :title="t('admin.paymentOperations.status')" :width="180">
                <template #cell="{ record }">
                  <Space wrap>
                    <Tag :color="statusColor(record.status)">{{ statusLabel(record.status) }}</Tag>
                    <Tag v-if="record.orphaned" color="magenta">
                      {{ t('admin.paymentOperations.orphan') }}
                    </Tag>
                  </Space>
                </template>
              </TableColumn>
              <TableColumn :title="t('admin.paymentOperations.amount')" :width="130" align="right">
                <template #cell="{ record }"><strong>{{ formatMoney(record) }}</strong></template>
              </TableColumn>
              <TableColumn :title="t('admin.paymentOperations.createdAt')" :width="190">
                <template #cell="{ record }">{{ formatTime(record.created_at) }}</template>
              </TableColumn>
            </template>

            <template v-else-if="view === 'webhooks'">
              <TableColumn :title="t('admin.paymentOperations.provider')" data-index="provider" :width="120" />
              <TableColumn
                :title="t('admin.paymentOperations.event')"
                data-index="event_type"
                :width="220"
                ellipsis
                tooltip
              />
              <TableColumn
                :title="t('admin.paymentOperations.eventReference')"
                data-index="event_reference"
                :width="180"
                ellipsis
                tooltip
              />
              <TableColumn :title="t('admin.paymentOperations.status')" :width="170">
                <template #cell="{ record }">
                  <Space wrap>
                    <Tag :color="statusColor(record.status)">{{ statusLabel(record.status) }}</Tag>
                    <Tag v-if="record.stale" color="magenta">{{ t('admin.paymentOperations.stale') }}</Tag>
                  </Space>
                </template>
              </TableColumn>
              <TableColumn :title="t('admin.paymentOperations.error')" :width="140">
                <template #cell="{ record }">
                  <Tag v-if="record.error_recorded" color="red">
                    {{ t('admin.paymentOperations.errorRecorded') }}
                  </Tag>
                  <span v-else>{{ t('admin.paymentOperations.noError') }}</span>
                </template>
              </TableColumn>
              <TableColumn :title="t('admin.paymentOperations.attempts')" :width="130">
                <template #cell="{ record }">
                  {{ record.attempt_count || 0 }} / {{ record.retry_count || 0 }}
                </template>
              </TableColumn>
              <TableColumn :title="t('admin.paymentOperations.nextRetry')" :width="190">
                <template #cell="{ record }">{{ formatTime(record.next_retry_at) }}</template>
              </TableColumn>
              <TableColumn :title="t('admin.paymentOperations.createdAt')" :width="190">
                <template #cell="{ record }">{{ formatTime(record.created_at) }}</template>
              </TableColumn>
              <TableColumn :title="t('admin.paymentOperations.updatedAt')" :width="190">
                <template #cell="{ record }">{{ formatTime(record.updated_at) }}</template>
              </TableColumn>
              <TableColumn
                v-if="replayEnabled"
                :title="t('admin.paymentOperations.actions')"
                :width="130"
                fixed="right"
              >
                <template #cell="{ record }">
                  <Button
                    v-if="record.replay"
                    type="outline"
                    status="warning"
                    size="small"
                    @click="openReplay(record)"
                  >
                    {{ t('admin.paymentOperations.replay') }}
                  </Button>
                </template>
              </TableColumn>
            </template>

            <template v-else>
              <TableColumn :title="t('admin.paymentOperations.order')" data-index="order_number" :width="170">
                <template #cell="{ record }">
                  <Link
                    :href="adminRoutes.storeOrder(record.order_id)"
                    class="arco-link font-medium no-underline"
                  >
                    {{ record.order_number }}
                  </Link>
                </template>
              </TableColumn>
              <TableColumn :title="t('admin.paymentOperations.provider')" data-index="provider" :width="110" />
              <TableColumn
                :title="t('admin.paymentOperations.reference')"
                data-index="provider_reference"
                :width="170"
                ellipsis
                tooltip
              />
              <TableColumn :title="t('admin.paymentOperations.status')" :width="150">
                <template #cell="{ record }">
                  <Space wrap>
                    <Tag :color="statusColor(record.status)">{{ statusLabel(record.status) }}</Tag>
                    <Tag v-if="record.stale" color="magenta">{{ t('admin.paymentOperations.stale') }}</Tag>
                  </Space>
                </template>
              </TableColumn>
              <TableColumn :title="t('admin.paymentOperations.providerStatus')" :width="150">
                <template #cell="{ record }">
                  <Tag v-if="record.provider_status" :color="statusColor(record.provider_status)">
                    {{ statusLabel(record.provider_status) }}
                  </Tag>
                  <span v-else>—</span>
                </template>
              </TableColumn>
              <TableColumn :title="t('admin.paymentOperations.amount')" :width="130" align="right">
                <template #cell="{ record }"><strong>{{ formatMoney(record) }}</strong></template>
              </TableColumn>
              <TableColumn :title="t('admin.paymentOperations.processingStartedAt')" :width="190">
                <template #cell="{ record }">{{ formatTime(record.processing_started_at) }}</template>
              </TableColumn>
              <TableColumn :title="t('admin.paymentOperations.updatedAt')" :width="190">
                <template #cell="{ record }">{{ formatTime(record.updated_at) }}</template>
              </TableColumn>
            </template>
          </template>
          <template #empty>
            <Empty :description="t('admin.paymentOperations.empty')" />
          </template>
        </Table>
      </div>

      <div class="mt-4 flex flex-wrap items-center justify-between gap-3">
        <TypographyText type="secondary">
          {{ t('admin.paymentOperations.range', {
            from: pagination.from || 0,
            to: pagination.to || 0,
            count: pagination.count,
          }) }}
        </TypographyText>
        <Pagination
          v-if="pagination.pages > 1"
          :current="pagination.page"
          :total="pagination.count"
          :page-size="40"
          :show-page-size="false"
          @change="visitPage"
        />
      </div>
    </Card>

    <Modal
      v-model:visible="replayVisible"
      :title="t('admin.paymentOperations.replayTitle')"
      :footer="false"
      :mask-closable="!replaySubmitting"
      :esc-to-close="!replaySubmitting"
      :width="'min(560px, calc(100vw - 32px))'"
    >
      <Alert
        type="warning"
        show-icon
        :closable="false"
        :title="t('admin.paymentOperations.replayWarning')"
        class="mb-4"
      />
      <div class="space-y-3">
        <TypographyText type="secondary">
          {{ t('admin.paymentOperations.replayEvent', {
            event: replayEvent?.event_type,
            reference: replayEvent?.event_reference,
          }) }}
        </TypographyText>
        <Textarea
          v-model="replayReason"
          :placeholder="t('admin.paymentOperations.replayReasonPlaceholder')"
          :max-length="500"
          show-word-limit
          :auto-size="{ minRows: 4, maxRows: 8 }"
          :disabled="replaySubmitting"
        />
        <TypographyText type="secondary">
          {{ t('admin.paymentOperations.replayReasonHelp') }}
        </TypographyText>
        <div class="flex flex-wrap justify-end gap-2 pt-2">
          <Button :disabled="replaySubmitting" @click="closeReplay">
            {{ t('admin.paymentOperations.cancel') }}
          </Button>
          <Button
            type="primary"
            status="danger"
            :loading="replaySubmitting"
            :disabled="replayReason.trim().length < 10 || replayReason.trim().length > 500"
            @click="submitReplay"
          >
            {{ t('admin.paymentOperations.confirmReplay') }}
          </Button>
        </div>
      </div>
    </Modal>
  </section>
</template>
