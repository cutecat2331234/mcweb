<script setup lang="ts">
import { computed, reactive, ref, watch } from 'vue'
import { router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { adminRoutes } from '@/lib/adminRoutes'
import { postJson } from '@/lib/http'

defineOptions({ layout: AdminLayout })

type ReviewAction = {
  url: string
  token: string
}

type ReconciliationRun = {
  id: number
  provider: string
  mode: 'test' | 'live'
  status: 'pending' | 'running' | 'completed' | 'failed' | 'skipped'
  phase: 'payments' | 'refunds' | 'local_checks' | 'completed'
  window_start: string
  window_end: string
  payments_checked: number
  refunds_checked: number
  discrepancies_count: number
  attempt_count: number
  failure_code?: string | null
  started_at?: string | null
  completed_at?: string | null
}

type ReconciliationRow = {
  id: string
  order_id?: string | null
  order_number?: string | null
  provider: string
  mode: 'test' | 'live'
  subject_type: 'payment' | 'refund'
  kind: string
  reference?: string | null
  status: 'open' | 'acknowledged' | 'ignored' | 'resolved'
  local_status?: string | null
  provider_status?: string | null
  local_amount_cents?: number | null
  provider_amount_cents?: number | null
  local_currency?: string | null
  provider_currency?: string | null
  run: ReconciliationRun
  review_note?: string | null
  reviewed_by?: string | null
  reviewed_at?: string | null
  first_seen_at: string
  last_seen_at: string
  action?: ReviewAction
}

type PaginationMeta = {
  page: number
  pages: number
  count: number
  from: number | null
  to: number | null
}

type ManualTrigger = {
  allowed: boolean
  ready: boolean
  url: string | null
  authorizationUrl: string | null
  token: string | null
  minDate: string
  maxDate: string
  defaultDate: string
  confirmation: string | null
}

const props = defineProps<{
  filters: {
    status: string | null
    kind: string | null
    subject_type: string | null
    provider: string | null
    mode: string | null
    q: string | null
  }
  filterOptions: {
    statuses: string[]
    kinds: string[]
    subject_types: string[]
    providers: string[]
    modes: string[]
  }
  summary: {
    total: number
    open: number
    acknowledged: number
    ignored: number
    resolved: number
  }
  runs: ReconciliationRun[]
  decisions: string[]
  rows: ReconciliationRow[]
  pagination: PaginationMeta
  reviewEnabled: boolean
  manualTrigger: ManualTrigger
}>()

const { locale, t, te } = useI18n()
const status = ref(props.filters.status || '')
const kind = ref(props.filters.kind || '')
const subjectType = ref(props.filters.subject_type || '')
const provider = ref(props.filters.provider || '')
const mode = ref(props.filters.mode || '')
const query = ref(props.filters.q || '')
const selected = ref<ReconciliationRow | null>(null)
const submitting = ref(false)
const manualOpen = ref(false)
const manualSubmitting = ref(false)
const manualAuthorizationLoading = ref(false)
const manualAuthorizationFailed = ref(false)
const manualToken = ref(props.manualTrigger.token)
const manualAuthorizedDate = ref(props.manualTrigger.defaultDate)
const manualAuthorizationConfirmation = ref(props.manualTrigger.confirmation || '')
let manualAuthorizationSequence = 0
const reviewForm = reactive({
  decision: '',
  note: '',
  confirmation: '',
})
const manualForm = reactive({
  date: props.manualTrigger.defaultDate,
  confirmation: '',
})

const modalVisible = computed({
  get: () => selected.value !== null,
  set: (visible: boolean) => {
    if (!visible) closeReview()
  },
})

const canSubmit = computed(() => {
  const noteLength = reviewForm.note.trim().length
  return Boolean(
    selected.value?.action &&
      props.decisions.includes(reviewForm.decision) &&
      noteLength >= 10 &&
      noteLength <= 1000 &&
      reviewForm.confirmation.trim() === selected.value.id,
  )
})

const manualModalVisible = computed({
  get: () => manualOpen.value,
  set: (visible: boolean) => {
    if (!visible) closeManualTrigger()
  },
})

const expectedManualConfirmation = computed(() => {
  if (!manualForm.date) return ''
  if (manualAuthorizedDate.value !== manualForm.date) return ''

  return manualAuthorizationConfirmation.value
})

const manualDateInRange = computed(() => isManualDateInRange(manualForm.date))

const canSubmitManual = computed(() =>
  Boolean(
    props.manualTrigger.allowed &&
      props.manualTrigger.ready &&
      props.manualTrigger.url &&
      manualToken.value &&
      manualDateInRange.value &&
      manualForm.confirmation === expectedManualConfirmation.value &&
      !manualAuthorizationLoading.value &&
      !manualSubmitting.value,
  ),
)

watch(
  () => props.filters,
  (filters) => {
    status.value = filters.status || ''
    kind.value = filters.kind || ''
    subjectType.value = filters.subject_type || ''
    provider.value = filters.provider || ''
    mode.value = filters.mode || ''
    query.value = filters.q || ''
  },
)

watch(
  () => props.manualTrigger,
  (manualTrigger) => {
    if (!manualOpen.value) {
      manualForm.date = manualTrigger.defaultDate
      manualToken.value = manualTrigger.token
      manualAuthorizedDate.value = manualTrigger.defaultDate
      manualAuthorizationConfirmation.value = manualTrigger.confirmation || ''
      manualAuthorizationFailed.value = false
    }
  },
)

watch(
  () => manualForm.date,
  (date) => {
    manualForm.confirmation = ''
    if (manualOpen.value) void refreshManualAuthorization(date)
  },
)

function translation(path: string, fallback: string) {
  return te(path) ? t(path) : fallback
}

function statusLabel(value: string) {
  return translation(`admin.paymentReconciliation.statuses.${value}`, value)
}

function statusColor(value: string) {
  if (value === 'completed' || value === 'acknowledged' || value === 'resolved') return 'green'
  if (value === 'failed') return 'red'
  if (value === 'running') return 'arcoblue'
  if (value === 'open') return 'orange'
  if (value === 'pending') return 'gold'
  return 'gray'
}

function kindLabel(value: string) {
  return translation(`admin.paymentReconciliation.kinds.${value}`, value)
}

function subjectLabel(value: string) {
  return translation(`admin.paymentReconciliation.subjects.${value}`, value)
}

function modeLabel(value: string) {
  return translation(`admin.paymentReconciliation.modes.${value}`, value)
}

function decisionLabel(value: string) {
  return translation(`admin.paymentReconciliation.decisions.${value}`, value)
}

function phaseLabel(value: string) {
  return translation(`admin.paymentReconciliation.phases.${value}`, value)
}

function formatMoney(amount: number | null | undefined, currency: string | null | undefined) {
  if (amount === null || amount === undefined || !currency) return '—'
  try {
    const formatter = new Intl.NumberFormat(locale.value, {
      style: 'currency',
      currency,
    })
    const fractionDigits = formatter.resolvedOptions().maximumFractionDigits ?? 2
    return formatter.format(amount / (10 ** fractionDigits))
  } catch {
    return `${amount} ${currency}`
  }
}

function formatTime(value: string | null | undefined) {
  if (!value) return '—'
  return new Intl.DateTimeFormat(locale.value, {
    dateStyle: 'short',
    timeStyle: 'short',
  }).format(new Date(value))
}

function formatWindow(run: ReconciliationRun) {
  const formatter = new Intl.DateTimeFormat(locale.value, {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    timeZone: 'UTC',
  })
  return `${formatter.format(new Date(run.window_start))} UTC`
}

function localIsoDate(value: Date) {
  const year = value.getFullYear()
  const month = String(value.getMonth() + 1).padStart(2, '0')
  const day = String(value.getDate()).padStart(2, '0')
  return `${year}-${month}-${day}`
}

function isManualDateInRange(value: string) {
  return (
    /^\d{4}-\d{2}-\d{2}$/.test(value) &&
    value >= props.manualTrigger.minDate &&
    value <= props.manualTrigger.maxDate
  )
}

function disabledManualDate(value: Date) {
  return !isManualDateInRange(localIsoDate(value))
}

function visit(patch: Record<string, string | number | undefined>) {
  const next: Record<string, string | number> = {
    ...(status.value ? { status: status.value } : {}),
    ...(kind.value ? { kind: kind.value } : {}),
    ...(subjectType.value ? { subject_type: subjectType.value } : {}),
    ...(provider.value ? { provider: provider.value } : {}),
    ...(mode.value ? { mode: mode.value } : {}),
    ...(query.value ? { q: query.value } : {}),
  }

  Object.entries(patch).forEach(([key, value]) => {
    if (value === undefined || value === '') delete next[key]
    else next[key] = value
  })

  router.get(adminRoutes.storePaymentReconciliations, next, {
    preserveScroll: true,
    preserveState: true,
    replace: true,
  })
}

function openReview(row: ReconciliationRow) {
  if (!row.action) return
  selected.value = row
  reviewForm.decision = ''
  reviewForm.note = ''
  reviewForm.confirmation = ''
}

function closeReview() {
  if (submitting.value) return
  selected.value = null
  reviewForm.decision = ''
  reviewForm.note = ''
  reviewForm.confirmation = ''
}

function submitReview() {
  if (!selected.value?.action || !canSubmit.value) return

  router.patch(
    selected.value.action.url,
    {
      token: selected.value.action.token,
      decision: reviewForm.decision,
      note: reviewForm.note.trim(),
      confirmation: reviewForm.confirmation.trim(),
    },
    {
      preserveScroll: true,
      onStart: () => {
        submitting.value = true
      },
      onSuccess: () => {
        selected.value = null
      },
      onFinish: () => {
        submitting.value = false
      },
    },
  )
}

function openManualTrigger() {
  if (
    !props.manualTrigger.allowed ||
    !props.manualTrigger.ready ||
    !props.manualTrigger.url ||
    !props.manualTrigger.authorizationUrl ||
    !props.manualTrigger.token ||
    manualSubmitting.value
  ) {
    return
  }

  manualAuthorizationSequence += 1
  manualForm.date = props.manualTrigger.defaultDate
  manualForm.confirmation = ''
  manualToken.value = props.manualTrigger.token
  manualAuthorizedDate.value = props.manualTrigger.defaultDate
  manualAuthorizationConfirmation.value = props.manualTrigger.confirmation || ''
  manualAuthorizationFailed.value = false
  manualAuthorizationLoading.value = false
  manualOpen.value = true
}

function closeManualTrigger() {
  if (manualSubmitting.value) return
  manualAuthorizationSequence += 1
  manualAuthorizationLoading.value = false
  manualOpen.value = false
  manualForm.confirmation = ''
}

async function refreshManualAuthorization(date: string) {
  const url = props.manualTrigger.authorizationUrl
  const sequence = ++manualAuthorizationSequence
  manualToken.value = null
  manualAuthorizedDate.value = ''
  manualAuthorizationConfirmation.value = ''
  manualAuthorizationFailed.value = false
  if (!url || !isManualDateInRange(date)) {
    manualAuthorizationFailed.value = true
    return
  }

  manualAuthorizationLoading.value = true
  try {
    const authorization = await postJson<{
      token: string
      confirmation: string
    }>(url, { date })
    if (sequence !== manualAuthorizationSequence || date !== manualForm.date) return

    manualToken.value = authorization.token
    manualAuthorizedDate.value = date
    manualAuthorizationConfirmation.value = authorization.confirmation
  } catch {
    if (sequence === manualAuthorizationSequence) {
      manualAuthorizationFailed.value = true
    }
  } finally {
    if (sequence === manualAuthorizationSequence) {
      manualAuthorizationLoading.value = false
    }
  }
}

function submitManualTrigger() {
  const url = props.manualTrigger.url
  const token = manualToken.value
  if (!url || !token || !canSubmitManual.value) return

  manualSubmitting.value = true
  try {
    router.post(
      url,
      {
        date: manualForm.date,
        confirmation: manualForm.confirmation,
        token,
      },
      {
        preserveScroll: true,
        onSuccess: () => {
          manualOpen.value = false
          manualToken.value = null
          manualForm.confirmation = ''
        },
        onFinish: () => {
          manualSubmitting.value = false
        },
      },
    )
  } catch (error) {
    manualSubmitting.value = false
    throw error
  }
}
</script>

<template>
  <a-space direction="vertical" :size="16" fill>
    <a-page-header
      :title="t('admin.paymentReconciliation.title')"
      :subtitle="t('admin.paymentReconciliation.subtitle')"
      :show-back="false"
    />
    <a-alert
      type="warning"
      show-icon
      :closable="false"
      :title="t('admin.paymentReconciliation.safetyNotice')"
    />
    <a-alert
      type="info"
      show-icon
      :closable="false"
      :title="t('admin.paymentReconciliation.scheduleNotice')"
    />

    <a-grid :cols="{ xs: 1, sm: 2, xl: 5 }" :col-gap="12" :row-gap="12">
      <a-grid-item>
        <a-card :bordered="false" size="small">
          <a-statistic :title="t('admin.paymentReconciliation.total')" :value="summary.total" />
        </a-card>
      </a-grid-item>
      <a-grid-item>
        <a-card :bordered="false" size="small">
          <a-statistic :title="t('admin.paymentReconciliation.open')" :value="summary.open" />
        </a-card>
      </a-grid-item>
      <a-grid-item>
        <a-card :bordered="false" size="small">
          <a-statistic
            :title="t('admin.paymentReconciliation.acknowledged')"
            :value="summary.acknowledged"
          />
        </a-card>
      </a-grid-item>
      <a-grid-item>
        <a-card :bordered="false" size="small">
          <a-statistic
            :title="t('admin.paymentReconciliation.ignored')"
            :value="summary.ignored"
          />
        </a-card>
      </a-grid-item>
      <a-grid-item>
        <a-card :bordered="false" size="small">
          <a-statistic
            :title="t('admin.paymentReconciliation.resolved')"
            :value="summary.resolved"
          />
        </a-card>
      </a-grid-item>
    </a-grid>

    <a-card v-if="manualTrigger.allowed" :bordered="false">
      <a-space direction="vertical" :size="16" fill>
        <a-space align="center" justify="space-between" wrap fill>
          <a-space direction="vertical" size="mini">
            <a-typography-title :heading="5">
              {{ t('admin.paymentReconciliation.manualTitle') }}
            </a-typography-title>
            <a-typography-text type="secondary">
              {{ t('admin.paymentReconciliation.manualHint') }}
            </a-typography-text>
          </a-space>
          <a-button
            v-if="manualTrigger.ready"
            type="primary"
            status="warning"
            :disabled="manualSubmitting"
            @click="openManualTrigger"
          >
            {{ t('admin.paymentReconciliation.manualOpen') }}
          </a-button>
        </a-space>
        <a-alert
          v-if="!manualTrigger.ready"
          type="warning"
          show-icon
          :closable="false"
          :title="t('admin.paymentReconciliation.manualUnavailable')"
        />
      </a-space>
    </a-card>

    <a-card :bordered="false">
      <template #title>
        <a-space direction="vertical" size="mini" fill>
          <a-typography-title :heading="5">
            {{ t('admin.paymentReconciliation.runHistory') }}
          </a-typography-title>
          <a-typography-text type="secondary">
            {{ t('admin.paymentReconciliation.runHistoryHint') }}
          </a-typography-text>
        </a-space>
      </template>
      <a-table
        :data="runs"
        :pagination="false"
        :bordered="false"
        :scroll="{ x: 1080 }"
        row-key="id"
        stripe
      >
        <template #columns>
          <a-table-column :title="t('admin.paymentReconciliation.window')" :width="180">
            <template #cell="{ record }">
              <a-space direction="vertical" size="mini" fill>
                <a-typography-text bold>{{ formatWindow(record) }}</a-typography-text>
                <a-tag size="small" :color="record.mode === 'live' ? 'red' : 'arcoblue'">
                  {{ modeLabel(record.mode) }}
                </a-tag>
              </a-space>
            </template>
          </a-table-column>
          <a-table-column :title="t('admin.paymentReconciliation.runState')" :width="190">
            <template #cell="{ record }">
              <a-space direction="vertical" size="mini" fill>
                <a-tag :color="statusColor(record.status)">
                  {{ statusLabel(record.status) }}
                </a-tag>
                <a-typography-text type="secondary">
                  {{ phaseLabel(record.phase) }}
                </a-typography-text>
              </a-space>
            </template>
          </a-table-column>
          <a-table-column :title="t('admin.paymentReconciliation.comparison')" :width="300">
            <template #cell="{ record }">
              <a-space direction="vertical" size="mini" fill>
                <a-typography-text>
                  {{ t('admin.paymentReconciliation.checked', {
                    payments: record.payments_checked,
                    refunds: record.refunds_checked,
                  }) }}
                </a-typography-text>
                <a-typography-text type="secondary">
                  {{ t('admin.paymentReconciliation.findings', {
                    count: record.discrepancies_count,
                  }) }}
                </a-typography-text>
              </a-space>
            </template>
          </a-table-column>
          <a-table-column
            :title="t('admin.paymentReconciliation.attempts', { count: '' })"
            :width="150"
          >
            <template #cell="{ record }">
              {{ t('admin.paymentReconciliation.attempts', { count: record.attempt_count }) }}
            </template>
          </a-table-column>
          <a-table-column :title="t('admin.paymentReconciliation.status')" :width="260">
            <template #cell="{ record }">
              <a-typography-text v-if="record.failure_code" type="danger">
                {{ t('admin.paymentReconciliation.failure', { code: record.failure_code }) }}
              </a-typography-text>
              <a-typography-text v-else type="secondary">
                {{ formatTime(record.completed_at || record.started_at) }}
              </a-typography-text>
            </template>
          </a-table-column>
        </template>
        <template #empty>
          <a-empty :description="t('admin.paymentReconciliation.noRuns')" />
        </template>
      </a-table>
    </a-card>

    <a-card :bordered="false">
      <a-space direction="vertical" :size="16" fill>
        <a-grid :cols="{ xs: 1, md: 2, xl: 6 }" :col-gap="12" :row-gap="12">
          <a-grid-item>
            <a-select
              v-model="status"
              allow-clear
              :placeholder="t('admin.paymentReconciliation.allStatuses')"
              @change="visit({ status: status || undefined, page: undefined })"
              @clear="visit({ status: undefined, page: undefined })"
            >
              <a-option v-for="item in filterOptions.statuses" :key="item" :value="item">
                {{ statusLabel(item) }}
              </a-option>
            </a-select>
          </a-grid-item>
          <a-grid-item>
            <a-select
              v-model="kind"
              allow-clear
              :placeholder="t('admin.paymentReconciliation.allKinds')"
              @change="visit({ kind: kind || undefined, page: undefined })"
              @clear="visit({ kind: undefined, page: undefined })"
            >
              <a-option v-for="item in filterOptions.kinds" :key="item" :value="item">
                {{ kindLabel(item) }}
              </a-option>
            </a-select>
          </a-grid-item>
          <a-grid-item>
            <a-select
              v-model="subjectType"
              allow-clear
              :placeholder="t('admin.paymentReconciliation.allSubjects')"
              @change="visit({ subject_type: subjectType || undefined, page: undefined })"
              @clear="visit({ subject_type: undefined, page: undefined })"
            >
              <a-option
                v-for="item in filterOptions.subject_types"
                :key="item"
                :value="item"
              >
                {{ subjectLabel(item) }}
              </a-option>
            </a-select>
          </a-grid-item>
          <a-grid-item>
            <a-select
              v-model="provider"
              allow-clear
              :placeholder="t('admin.paymentReconciliation.allProviders')"
              @change="visit({ provider: provider || undefined, page: undefined })"
              @clear="visit({ provider: undefined, page: undefined })"
            >
              <a-option v-for="item in filterOptions.providers" :key="item" :value="item">
                {{ item }}
              </a-option>
            </a-select>
          </a-grid-item>
          <a-grid-item>
            <a-select
              v-model="mode"
              allow-clear
              :placeholder="t('admin.paymentReconciliation.allModes')"
              @change="visit({ mode: mode || undefined, page: undefined })"
              @clear="visit({ mode: undefined, page: undefined })"
            >
              <a-option v-for="item in filterOptions.modes" :key="item" :value="item">
                {{ modeLabel(item) }}
              </a-option>
            </a-select>
          </a-grid-item>
          <a-grid-item>
            <a-input-search
              v-model="query"
              allow-clear
              search-button
              :placeholder="t('admin.paymentReconciliation.searchPlaceholder')"
              @search="visit({ q: query || undefined, page: undefined })"
              @clear="visit({ q: undefined, page: undefined })"
            />
          </a-grid-item>
        </a-grid>

        <a-alert
          type="info"
          show-icon
          :closable="false"
          :title="t('admin.paymentReconciliation.scrollHint')"
        />

        <a-table
          :data="rows"
          :pagination="false"
          :bordered="false"
          :scroll="{ x: 1710 }"
          row-key="id"
          stripe
        >
          <template #columns>
            <a-table-column
              :title="t('admin.paymentReconciliation.discrepancy')"
              :width="270"
            >
              <template #cell="{ record }">
                <a-space direction="vertical" size="mini" fill>
                  <a-typography-text code ellipsis>{{ record.id }}</a-typography-text>
                  <a-typography-text bold ellipsis>{{ kindLabel(record.kind) }}</a-typography-text>
                  <a-space wrap>
                    <a-tag
                      :color="record.subject_type === 'payment' ? 'arcoblue' : 'purple'"
                    >
                      {{ subjectLabel(record.subject_type) }}
                    </a-tag>
                    <a-tag :color="statusColor(record.status)">
                      {{ statusLabel(record.status) }}
                    </a-tag>
                  </a-space>
                </a-space>
              </template>
            </a-table-column>
            <a-table-column :title="t('admin.paymentReconciliation.order')" :width="190">
              <template #cell="{ record }">
                <a-link
                  v-if="record.order_id"
                  @click="router.visit(adminRoutes.storeOrder(record.order_id))"
                >
                  {{ record.order_number }}
                </a-link>
                <a-typography-text v-else type="secondary">—</a-typography-text>
              </template>
            </a-table-column>
            <a-table-column :title="t('admin.paymentReconciliation.reference')" :width="210">
              <template #cell="{ record }">
                <a-space direction="vertical" size="mini" fill>
                  <a-tag :color="record.mode === 'live' ? 'red' : 'arcoblue'">
                    {{ record.provider }} · {{ modeLabel(record.mode) }}
                  </a-tag>
                  <a-typography-text code ellipsis>
                    {{ record.reference || '—' }}
                  </a-typography-text>
                </a-space>
              </template>
            </a-table-column>
            <a-table-column :title="t('admin.paymentReconciliation.local')" :width="200">
              <template #cell="{ record }">
                <a-space direction="vertical" size="mini" fill>
                  <a-typography-text bold>
                    {{ formatMoney(record.local_amount_cents, record.local_currency) }}
                  </a-typography-text>
                  <a-typography-text type="secondary">
                    {{ record.local_status ? statusLabel(record.local_status) : '—' }}
                  </a-typography-text>
                </a-space>
              </template>
            </a-table-column>
            <a-table-column :title="t('admin.paymentReconciliation.provider')" :width="200">
              <template #cell="{ record }">
                <a-space direction="vertical" size="mini" fill>
                  <a-typography-text bold>
                    {{ formatMoney(record.provider_amount_cents, record.provider_currency) }}
                  </a-typography-text>
                  <a-typography-text type="secondary">
                    {{ record.provider_status ? statusLabel(record.provider_status) : '—' }}
                  </a-typography-text>
                </a-space>
              </template>
            </a-table-column>
            <a-table-column :title="t('admin.paymentReconciliation.window')" :width="210">
              <template #cell="{ record }">
                <a-space direction="vertical" size="mini" fill>
                  <a-typography-text>{{ formatWindow(record.run) }}</a-typography-text>
                  <a-typography-text type="secondary">
                    {{ formatTime(record.first_seen_at) }}
                  </a-typography-text>
                  <a-typography-text type="secondary">
                    {{ formatTime(record.last_seen_at) }}
                  </a-typography-text>
                </a-space>
              </template>
            </a-table-column>
            <a-table-column :title="t('admin.paymentReconciliation.review')" :width="300">
              <template #cell="{ record }">
                <a-space v-if="record.status === 'resolved'" direction="vertical" size="mini">
                  <a-typography-text bold>{{ statusLabel(record.status) }}</a-typography-text>
                  <a-typography-text type="secondary">
                    {{ t('admin.paymentReconciliation.autoResolved') }}
                  </a-typography-text>
                </a-space>
                <a-space
                  v-else-if="record.status !== 'open'"
                  direction="vertical"
                  size="mini"
                  fill
                >
                  <a-typography-text bold>{{ statusLabel(record.status) }}</a-typography-text>
                  <a-typography-text type="secondary">
                    {{ t('admin.paymentReconciliation.reviewedBy', {
                      user: record.reviewed_by,
                      time: formatTime(record.reviewed_at),
                    }) }}
                  </a-typography-text>
                  <a-typography-paragraph
                    v-if="record.review_note"
                    :ellipsis="{ rows: 2, showTooltip: true }"
                  >
                    {{ record.review_note }}
                  </a-typography-paragraph>
                </a-space>
                <a-typography-text v-else type="secondary">
                  {{ t('admin.paymentReconciliation.noReview') }}
                </a-typography-text>
              </template>
            </a-table-column>
            <a-table-column
              :title="t('admin.paymentReconciliation.actions')"
              :width="120"
              fixed="right"
            >
              <template #cell="{ record }">
                <a-button
                  v-if="record.action"
                  type="outline"
                  status="warning"
                  size="small"
                  @click="openReview(record)"
                >
                  {{ t('admin.paymentReconciliation.reviewAction') }}
                </a-button>
              </template>
            </a-table-column>
          </template>
          <template #empty>
            <a-empty :description="t('admin.paymentReconciliation.empty')" />
          </template>
        </a-table>

        <a-space align="center" justify="space-between" wrap fill>
          <a-typography-text type="secondary">
            {{ t('admin.paymentReconciliation.range', {
              from: pagination.from || 0,
              to: pagination.to || 0,
              count: pagination.count,
            }) }}
          </a-typography-text>
          <a-pagination
            v-if="pagination.pages > 1"
            :current="pagination.page"
            :total="pagination.count"
            :page-size="40"
            :show-page-size="false"
            @change="visit({ page: $event })"
          />
        </a-space>
      </a-space>
    </a-card>

    <a-modal
      v-model:visible="manualModalVisible"
      :title="t('admin.paymentReconciliation.manualDialogTitle')"
      :footer="false"
      :mask-closable="!manualSubmitting && !manualAuthorizationLoading"
      :esc-to-close="!manualSubmitting && !manualAuthorizationLoading"
      width="560px"
    >
      <a-space direction="vertical" :size="16" fill>
        <a-alert
          type="warning"
          show-icon
          :closable="false"
          :title="t('admin.paymentReconciliation.manualWarning')"
        />
        <a-form :model="manualForm" layout="vertical">
          <a-form-item
            field="date"
            :label="t('admin.paymentReconciliation.manualDate')"
            required
          >
            <a-date-picker
              v-model="manualForm.date"
              value-format="YYYY-MM-DD"
              format="YYYY-MM-DD"
              :allow-clear="false"
              :disabled-date="disabledManualDate"
              :disabled="manualSubmitting || manualAuthorizationLoading"
              :placeholder="t('admin.paymentReconciliation.manualDatePlaceholder')"
            />
            <template #extra>
              {{ t('admin.paymentReconciliation.manualRange', {
                min: manualTrigger.minDate,
                max: manualTrigger.maxDate,
              }) }}
            </template>
          </a-form-item>
          <a-alert
            v-if="manualAuthorizationFailed"
            type="error"
            show-icon
            :closable="false"
            :title="t('admin.paymentReconciliation.manualUnavailable')"
          />
          <a-form-item
            field="confirmation"
            :label="t('admin.paymentReconciliation.manualConfirmation')"
            required
          >
            <a-input
              v-model="manualForm.confirmation"
              :placeholder="t('admin.paymentReconciliation.manualConfirmationPlaceholder', {
                confirmation: expectedManualConfirmation,
              })"
              :disabled="manualSubmitting || manualAuthorizationLoading"
              autocomplete="off"
            />
            <template #extra>
              {{ t('admin.paymentReconciliation.manualConfirmationHelp', {
                confirmation: expectedManualConfirmation,
              }) }}
            </template>
          </a-form-item>
        </a-form>
        <a-space justify="end" wrap fill>
          <a-button
            :disabled="manualSubmitting || manualAuthorizationLoading"
            @click="closeManualTrigger"
          >
            {{ t('admin.paymentReconciliation.cancel') }}
          </a-button>
          <a-button
            type="primary"
            status="warning"
            :loading="manualSubmitting || manualAuthorizationLoading"
            :disabled="!canSubmitManual"
            @click="submitManualTrigger"
          >
            {{ t('admin.paymentReconciliation.manualSubmit') }}
          </a-button>
        </a-space>
      </a-space>
    </a-modal>

    <a-modal
      v-model:visible="modalVisible"
      :title="t('admin.paymentReconciliation.reviewTitle')"
      :footer="false"
      :mask-closable="!submitting"
      :esc-to-close="!submitting"
      width="620px"
    >
      <a-space direction="vertical" :size="16" fill>
        <a-alert
          type="warning"
          show-icon
          :closable="false"
          :title="t('admin.paymentReconciliation.reviewWarning')"
        />
        <a-form :model="reviewForm" layout="vertical">
          <a-form-item
            field="decision"
            :label="t('admin.paymentReconciliation.decision')"
            required
          >
            <a-select
              v-model="reviewForm.decision"
              :placeholder="t('admin.paymentReconciliation.decisionPlaceholder')"
              :disabled="submitting"
            >
              <a-option v-for="item in decisions" :key="item" :value="item">
                {{ decisionLabel(item) }}
              </a-option>
            </a-select>
          </a-form-item>
          <a-form-item field="note" :label="t('admin.paymentReconciliation.note')" required>
            <a-textarea
              v-model="reviewForm.note"
              :placeholder="t('admin.paymentReconciliation.notePlaceholder')"
              :max-length="1000"
              show-word-limit
              :auto-size="{ minRows: 4, maxRows: 8 }"
              :disabled="submitting"
            />
            <template #extra>{{ t('admin.paymentReconciliation.noteHelp') }}</template>
          </a-form-item>
          <a-form-item
            field="confirmation"
            :label="t('admin.paymentReconciliation.confirmation')"
            required
          >
            <a-input
              v-model="reviewForm.confirmation"
              :placeholder="t('admin.paymentReconciliation.confirmationPlaceholder', {
                id: selected?.id,
              })"
              :disabled="submitting"
              autocomplete="off"
            />
            <template #extra>
              {{ t('admin.paymentReconciliation.confirmationHelp') }}
            </template>
          </a-form-item>
        </a-form>
        <a-space justify="end" wrap fill>
          <a-button :disabled="submitting" @click="closeReview">
            {{ t('admin.paymentReconciliation.cancel') }}
          </a-button>
          <a-button
            type="primary"
            status="danger"
            :loading="submitting"
            :disabled="!canSubmit"
            @click="submitReview"
          >
            {{ t('admin.paymentReconciliation.confirmReview') }}
          </a-button>
        </a-space>
      </a-space>
    </a-modal>
  </a-space>
</template>
