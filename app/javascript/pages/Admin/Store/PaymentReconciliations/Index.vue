<script setup lang="ts">
import { computed, reactive, ref, watch } from 'vue'
import { Link, router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import {
  Alert,
  Button,
  Card,
  DatePicker,
  Empty,
  Form,
  FormItem,
  Grid,
  GridItem,
  Input,
  InputSearch,
  Modal,
  Option,
  PageHeader,
  Pagination,
  Select,
  Statistic,
  Table,
  TableColumn,
  Tag,
  Textarea,
  TypographyText,
} from '@mcweb/ui'
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
    const fractionDigits = formatter.resolvedOptions().maximumFractionDigits
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
  <section>
    <PageHeader
      :title="t('admin.paymentReconciliation.title')"
      :subtitle="t('admin.paymentReconciliation.subtitle')"
      :show-back="false"
      class="mb-5 !px-0"
    />

    <Alert
      type="warning"
      show-icon
      :closable="false"
      :title="t('admin.paymentReconciliation.safetyNotice')"
      class="mb-3"
    />
    <Alert
      type="info"
      show-icon
      :closable="false"
      :title="t('admin.paymentReconciliation.scheduleNotice')"
      class="mb-5"
    />

    <Grid :cols="{ xs: 1, sm: 2, xl: 5 }" :col-gap="16" :row-gap="16" class="mb-5">
      <GridItem>
        <Card :bordered="false" class="bg-[var(--color-fill-1)]">
          <Statistic :title="t('admin.paymentReconciliation.total')" :value="summary.total" />
        </Card>
      </GridItem>
      <GridItem>
        <Card :bordered="false" class="bg-[var(--color-fill-1)]">
          <Statistic :title="t('admin.paymentReconciliation.open')" :value="summary.open" />
        </Card>
      </GridItem>
      <GridItem>
        <Card :bordered="false" class="bg-[var(--color-fill-1)]">
          <Statistic
            :title="t('admin.paymentReconciliation.acknowledged')"
            :value="summary.acknowledged"
          />
        </Card>
      </GridItem>
      <GridItem>
        <Card :bordered="false" class="bg-[var(--color-fill-1)]">
          <Statistic :title="t('admin.paymentReconciliation.ignored')" :value="summary.ignored" />
        </Card>
      </GridItem>
      <GridItem>
        <Card :bordered="false" class="bg-[var(--color-fill-1)]">
          <Statistic :title="t('admin.paymentReconciliation.resolved')" :value="summary.resolved" />
        </Card>
      </GridItem>
    </Grid>

    <Card v-if="manualTrigger.allowed" :bordered="false" class="mb-5">
      <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div class="min-w-0 max-w-3xl">
          <h2 class="text-lg font-semibold">
            {{ t('admin.paymentReconciliation.manualTitle') }}
          </h2>
          <TypographyText type="secondary" class="mt-1 block leading-6">
            {{ t('admin.paymentReconciliation.manualHint') }}
          </TypographyText>
        </div>

        <Button
          v-if="manualTrigger.ready"
          type="primary"
          status="warning"
          class="w-full shrink-0 sm:w-auto"
          :disabled="manualSubmitting"
          @click="openManualTrigger"
        >
          {{ t('admin.paymentReconciliation.manualOpen') }}
        </Button>
      </div>

      <Alert
        v-if="!manualTrigger.ready"
        type="warning"
        show-icon
        :closable="false"
        :title="t('admin.paymentReconciliation.manualUnavailable')"
        class="mt-4"
      />
    </Card>

    <Card :bordered="false" class="mb-5">
      <div class="mb-4 flex flex-wrap items-start justify-between gap-2">
        <div>
          <h2 class="text-lg font-semibold">{{ t('admin.paymentReconciliation.runHistory') }}</h2>
          <TypographyText type="secondary">
            {{ t('admin.paymentReconciliation.runHistoryHint') }}
          </TypographyText>
        </div>
      </div>

      <div class="overflow-x-auto">
        <Table
          :data="runs"
          :pagination="false"
          :bordered="false"
          :scroll="{ minWidth: 1080 }"
          row-key="id"
          stripe
        >
          <template #columns>
            <TableColumn :title="t('admin.paymentReconciliation.window')" :width="170">
              <template #cell="{ record }">
                <div class="space-y-1">
                  <p class="font-medium">{{ formatWindow(record) }}</p>
                  <Tag size="small" :color="record.mode === 'live' ? 'red' : 'arcoblue'">
                    {{ modeLabel(record.mode) }}
                  </Tag>
                </div>
              </template>
            </TableColumn>
            <TableColumn :title="t('admin.paymentReconciliation.runState')" :width="190">
              <template #cell="{ record }">
                <div class="space-y-1">
                  <Tag :color="statusColor(record.status)">{{ statusLabel(record.status) }}</Tag>
                  <p class="text-xs text-[var(--color-text-3)]">{{ phaseLabel(record.phase) }}</p>
                </div>
              </template>
            </TableColumn>
            <TableColumn :title="t('admin.paymentReconciliation.comparison')" :width="280">
              <template #cell="{ record }">
                <div class="space-y-1 text-sm">
                  <p>
                    {{ t('admin.paymentReconciliation.checked', {
                      payments: record.payments_checked,
                      refunds: record.refunds_checked,
                    }) }}
                  </p>
                  <p class="text-[var(--color-text-3)]">
                    {{ t('admin.paymentReconciliation.findings', {
                      count: record.discrepancies_count,
                    }) }}
                  </p>
                </div>
              </template>
            </TableColumn>
            <TableColumn :title="t('admin.paymentReconciliation.attempts', { count: '' })" :width="150">
              <template #cell="{ record }">
                {{ t('admin.paymentReconciliation.attempts', { count: record.attempt_count }) }}
              </template>
            </TableColumn>
            <TableColumn :title="t('admin.paymentReconciliation.status')" :width="240">
              <template #cell="{ record }">
                <TypographyText v-if="record.failure_code" type="danger">
                  {{ t('admin.paymentReconciliation.failure', { code: record.failure_code }) }}
                </TypographyText>
                <TypographyText v-else type="secondary">
                  {{ formatTime(record.completed_at || record.started_at) }}
                </TypographyText>
              </template>
            </TableColumn>
          </template>
          <template #empty>
            <Empty :description="t('admin.paymentReconciliation.noRuns')" />
          </template>
        </Table>
      </div>
    </Card>

    <Card :bordered="false">
      <div class="mb-5 grid gap-3 md:grid-cols-2 xl:grid-cols-6">
        <Select
          v-model="status"
          allow-clear
          :placeholder="t('admin.paymentReconciliation.allStatuses')"
          class="w-full"
          @change="visit({ status: status || undefined, page: undefined })"
          @clear="visit({ status: undefined, page: undefined })"
        >
          <Option v-for="item in filterOptions.statuses" :key="item" :value="item">
            {{ statusLabel(item) }}
          </Option>
        </Select>

        <Select
          v-model="kind"
          allow-clear
          :placeholder="t('admin.paymentReconciliation.allKinds')"
          class="w-full"
          @change="visit({ kind: kind || undefined, page: undefined })"
          @clear="visit({ kind: undefined, page: undefined })"
        >
          <Option v-for="item in filterOptions.kinds" :key="item" :value="item">
            {{ kindLabel(item) }}
          </Option>
        </Select>

        <Select
          v-model="subjectType"
          allow-clear
          :placeholder="t('admin.paymentReconciliation.allSubjects')"
          class="w-full"
          @change="visit({ subject_type: subjectType || undefined, page: undefined })"
          @clear="visit({ subject_type: undefined, page: undefined })"
        >
          <Option v-for="item in filterOptions.subject_types" :key="item" :value="item">
            {{ subjectLabel(item) }}
          </Option>
        </Select>

        <Select
          v-model="provider"
          allow-clear
          :placeholder="t('admin.paymentReconciliation.allProviders')"
          class="w-full"
          @change="visit({ provider: provider || undefined, page: undefined })"
          @clear="visit({ provider: undefined, page: undefined })"
        >
          <Option v-for="item in filterOptions.providers" :key="item" :value="item">
            {{ item }}
          </Option>
        </Select>

        <Select
          v-model="mode"
          allow-clear
          :placeholder="t('admin.paymentReconciliation.allModes')"
          class="w-full"
          @change="visit({ mode: mode || undefined, page: undefined })"
          @clear="visit({ mode: undefined, page: undefined })"
        >
          <Option v-for="item in filterOptions.modes" :key="item" :value="item">
            {{ modeLabel(item) }}
          </Option>
        </Select>

        <InputSearch
          v-model="query"
          allow-clear
          search-button
          :placeholder="t('admin.paymentReconciliation.searchPlaceholder')"
          class="w-full md:col-span-2 xl:col-span-1"
          @search="visit({ q: query || undefined, page: undefined })"
          @clear="visit({ q: undefined, page: undefined })"
        />
      </div>

      <TypographyText type="secondary" class="mb-3 hidden lg:block">
        {{ t('admin.paymentReconciliation.scrollHint') }}
      </TypographyText>

      <div class="hidden overflow-x-auto lg:block">
        <Table
          :data="rows"
          :pagination="false"
          :bordered="false"
          :scroll="{ minWidth: 1710 }"
          row-key="id"
          stripe
        >
          <template #columns>
            <TableColumn :title="t('admin.paymentReconciliation.discrepancy')" :width="270">
              <template #cell="{ record }">
                <div class="min-w-0 space-y-1.5">
                  <p class="truncate font-mono text-xs" :title="record.id">{{ record.id }}</p>
                  <p class="line-clamp-2 font-medium" :title="kindLabel(record.kind)">
                    {{ kindLabel(record.kind) }}
                  </p>
                  <div class="flex flex-wrap gap-1">
                    <Tag :color="record.subject_type === 'payment' ? 'arcoblue' : 'purple'">
                      {{ subjectLabel(record.subject_type) }}
                    </Tag>
                    <Tag :color="statusColor(record.status)">{{ statusLabel(record.status) }}</Tag>
                  </div>
                </div>
              </template>
            </TableColumn>

            <TableColumn :title="t('admin.paymentReconciliation.order')" :width="190">
              <template #cell="{ record }">
                <Link
                  v-if="record.order_id"
                  :href="adminRoutes.storeOrder(record.order_id)"
                  class="arco-link font-medium no-underline"
                >
                  {{ record.order_number }}
                </Link>
                <TypographyText v-else type="secondary">—</TypographyText>
              </template>
            </TableColumn>

            <TableColumn :title="t('admin.paymentReconciliation.reference')" :width="190">
              <template #cell="{ record }">
                <div class="space-y-1">
                  <Tag :color="record.mode === 'live' ? 'red' : 'arcoblue'">
                    {{ record.provider }} · {{ modeLabel(record.mode) }}
                  </Tag>
                  <p class="truncate font-mono text-xs" :title="record.reference || undefined">
                    {{ record.reference || '—' }}
                  </p>
                </div>
              </template>
            </TableColumn>

            <TableColumn :title="t('admin.paymentReconciliation.local')" :width="200">
              <template #cell="{ record }">
                <div class="space-y-1">
                  <p class="font-semibold">
                    {{ formatMoney(record.local_amount_cents, record.local_currency) }}
                  </p>
                  <TypographyText type="secondary">
                    {{ record.local_status ? statusLabel(record.local_status) : '—' }}
                  </TypographyText>
                </div>
              </template>
            </TableColumn>

            <TableColumn :title="t('admin.paymentReconciliation.provider')" :width="200">
              <template #cell="{ record }">
                <div class="space-y-1">
                  <p class="font-semibold">
                    {{ formatMoney(record.provider_amount_cents, record.provider_currency) }}
                  </p>
                  <TypographyText type="secondary">
                    {{ record.provider_status ? statusLabel(record.provider_status) : '—' }}
                  </TypographyText>
                </div>
              </template>
            </TableColumn>

            <TableColumn :title="t('admin.paymentReconciliation.window')" :width="170">
              <template #cell="{ record }">
                <div class="space-y-1">
                  <p>{{ formatWindow(record.run) }}</p>
                  <TypographyText type="secondary">
                    {{ formatTime(record.first_seen_at) }}
                  </TypographyText>
                </div>
              </template>
            </TableColumn>

            <TableColumn :title="t('admin.paymentReconciliation.review')" :width="290">
              <template #cell="{ record }">
                <div v-if="record.status === 'resolved'" class="space-y-1">
                  <p class="font-medium">{{ statusLabel(record.status) }}</p>
                  <p class="text-xs text-[var(--color-text-3)]">
                    {{ t('admin.paymentReconciliation.autoResolved') }}
                  </p>
                </div>
                <div v-else-if="record.status !== 'open'" class="space-y-1">
                  <p class="font-medium">{{ statusLabel(record.status) }}</p>
                  <p class="text-xs text-[var(--color-text-3)]">
                    {{ t('admin.paymentReconciliation.reviewedBy', {
                      user: record.reviewed_by,
                      time: formatTime(record.reviewed_at),
                    }) }}
                  </p>
                  <p v-if="record.review_note" class="line-clamp-2 text-sm text-[var(--color-text-2)]">
                    {{ record.review_note }}
                  </p>
                </div>
                <TypographyText v-else type="secondary">
                  {{ t('admin.paymentReconciliation.noReview') }}
                </TypographyText>
              </template>
            </TableColumn>

            <TableColumn :title="t('admin.paymentReconciliation.actions')" :width="120" fixed="right">
              <template #cell="{ record }">
                <Button
                  v-if="record.action"
                  type="outline"
                  status="warning"
                  size="small"
                  @click="openReview(record)"
                >
                  {{ t('admin.paymentReconciliation.reviewAction') }}
                </Button>
              </template>
            </TableColumn>
          </template>
          <template #empty>
            <Empty :description="t('admin.paymentReconciliation.empty')" />
          </template>
        </Table>
      </div>

      <div class="space-y-3 lg:hidden">
        <Card
          v-for="row in rows"
          :key="row.id"
          :bordered="false"
          class="bg-[var(--color-fill-1)]"
        >
          <div class="space-y-4">
            <div class="flex flex-wrap items-start justify-between gap-2">
              <div class="min-w-0 flex-1">
                <p class="truncate font-mono text-xs text-[var(--color-text-3)]">{{ row.id }}</p>
                <p class="mt-1 font-semibold">{{ kindLabel(row.kind) }}</p>
              </div>
              <Tag :color="statusColor(row.status)">{{ statusLabel(row.status) }}</Tag>
            </div>

            <div class="flex flex-wrap gap-1.5">
              <Tag :color="row.subject_type === 'payment' ? 'arcoblue' : 'purple'">
                {{ subjectLabel(row.subject_type) }}
              </Tag>
              <Tag :color="row.mode === 'live' ? 'red' : 'arcoblue'">
                {{ row.provider }} · {{ modeLabel(row.mode) }}
              </Tag>
              <Tag v-if="row.reference">{{ row.reference }}</Tag>
            </div>

            <Link
              v-if="row.order_id"
              :href="adminRoutes.storeOrder(row.order_id)"
              class="arco-link inline-block font-medium no-underline"
            >
              {{ row.order_number }}
            </Link>

            <div class="grid gap-3 sm:grid-cols-2">
              <div class="rounded-md bg-[var(--color-bg-2)] p-3">
                <p class="mb-1 text-xs text-[var(--color-text-3)]">
                  {{ t('admin.paymentReconciliation.local') }}
                </p>
                <p class="font-semibold">
                  {{ formatMoney(row.local_amount_cents, row.local_currency) }}
                </p>
                <p class="mt-1 text-sm">{{ row.local_status ? statusLabel(row.local_status) : '—' }}</p>
              </div>
              <div class="rounded-md bg-[var(--color-bg-2)] p-3">
                <p class="mb-1 text-xs text-[var(--color-text-3)]">
                  {{ t('admin.paymentReconciliation.provider') }}
                </p>
                <p class="font-semibold">
                  {{ formatMoney(row.provider_amount_cents, row.provider_currency) }}
                </p>
                <p class="mt-1 text-sm">
                  {{ row.provider_status ? statusLabel(row.provider_status) : '—' }}
                </p>
              </div>
            </div>

            <div class="flex flex-wrap items-center justify-between gap-3 text-sm">
              <TypographyText type="secondary">{{ formatWindow(row.run) }}</TypographyText>
              <Button
                v-if="row.action"
                type="outline"
                status="warning"
                size="small"
                @click="openReview(row)"
              >
                {{ t('admin.paymentReconciliation.reviewAction') }}
              </Button>
            </div>
          </div>
        </Card>
        <Empty v-if="rows.length === 0" :description="t('admin.paymentReconciliation.empty')" />
      </div>

      <div class="mt-5 flex flex-wrap items-center justify-between gap-3">
        <TypographyText type="secondary">
          {{ t('admin.paymentReconciliation.range', {
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
          @change="visit({ page: $event })"
        />
      </div>
    </Card>

    <Modal
      v-model:visible="manualModalVisible"
      :title="t('admin.paymentReconciliation.manualDialogTitle')"
      :footer="false"
      :mask-closable="!manualSubmitting && !manualAuthorizationLoading"
      :esc-to-close="!manualSubmitting && !manualAuthorizationLoading"
      :width="'min(560px, calc(100vw - 32px))'"
    >
      <Alert
        type="warning"
        show-icon
        :closable="false"
        :title="t('admin.paymentReconciliation.manualWarning')"
        class="mb-5"
      />

      <Form :model="manualForm" layout="vertical">
        <FormItem
          field="date"
          :label="t('admin.paymentReconciliation.manualDate')"
          required
        >
          <DatePicker
            v-model="manualForm.date"
            value-format="YYYY-MM-DD"
            format="YYYY-MM-DD"
            :allow-clear="false"
            :disabled-date="disabledManualDate"
            :disabled="manualSubmitting || manualAuthorizationLoading"
            :placeholder="t('admin.paymentReconciliation.manualDatePlaceholder')"
            class="w-full"
          />
          <template #extra>
            {{ t('admin.paymentReconciliation.manualRange', {
              min: manualTrigger.minDate,
              max: manualTrigger.maxDate,
            }) }}
          </template>
        </FormItem>

        <Alert
          v-if="manualAuthorizationFailed"
          type="error"
          show-icon
          :closable="false"
          :title="t('admin.paymentReconciliation.manualUnavailable')"
          class="mb-4"
        />

        <FormItem
          field="confirmation"
          :label="t('admin.paymentReconciliation.manualConfirmation')"
          required
        >
          <Input
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
        </FormItem>
      </Form>

      <div class="flex flex-col-reverse gap-2 pt-2 sm:flex-row sm:justify-end">
        <Button
          class="w-full sm:w-auto"
          :disabled="manualSubmitting || manualAuthorizationLoading"
          @click="closeManualTrigger"
        >
          {{ t('admin.paymentReconciliation.cancel') }}
        </Button>
        <Button
          type="primary"
          status="warning"
          class="w-full sm:w-auto"
          :loading="manualSubmitting || manualAuthorizationLoading"
          :disabled="!canSubmitManual"
          @click="submitManualTrigger"
        >
          {{ t('admin.paymentReconciliation.manualSubmit') }}
        </Button>
      </div>
    </Modal>

    <Modal
      v-model:visible="modalVisible"
      :title="t('admin.paymentReconciliation.reviewTitle')"
      :footer="false"
      :mask-closable="!submitting"
      :esc-to-close="!submitting"
      :width="'min(620px, calc(100vw - 32px))'"
    >
      <Alert
        type="warning"
        show-icon
        :closable="false"
        :title="t('admin.paymentReconciliation.reviewWarning')"
        class="mb-5"
      />

      <Form :model="reviewForm" layout="vertical">
        <FormItem field="decision" :label="t('admin.paymentReconciliation.decision')" required>
          <Select
            v-model="reviewForm.decision"
            :placeholder="t('admin.paymentReconciliation.decisionPlaceholder')"
            :disabled="submitting"
          >
            <Option v-for="item in decisions" :key="item" :value="item">
              {{ decisionLabel(item) }}
            </Option>
          </Select>
        </FormItem>

        <FormItem field="note" :label="t('admin.paymentReconciliation.note')" required>
          <Textarea
            v-model="reviewForm.note"
            :placeholder="t('admin.paymentReconciliation.notePlaceholder')"
            :max-length="1000"
            show-word-limit
            :auto-size="{ minRows: 4, maxRows: 8 }"
            :disabled="submitting"
          />
          <template #extra>{{ t('admin.paymentReconciliation.noteHelp') }}</template>
        </FormItem>

        <FormItem
          field="confirmation"
          :label="t('admin.paymentReconciliation.confirmation')"
          required
        >
          <Input
            v-model="reviewForm.confirmation"
            :placeholder="t('admin.paymentReconciliation.confirmationPlaceholder', {
              id: selected?.id,
            })"
            :disabled="submitting"
            autocomplete="off"
          />
          <template #extra>{{ t('admin.paymentReconciliation.confirmationHelp') }}</template>
        </FormItem>
      </Form>

      <div class="flex flex-wrap justify-end gap-2 pt-2">
        <Button :disabled="submitting" @click="closeReview">
          {{ t('admin.paymentReconciliation.cancel') }}
        </Button>
        <Button
          type="primary"
          status="danger"
          :loading="submitting"
          :disabled="!canSubmit"
          @click="submitReview"
        >
          {{ t('admin.paymentReconciliation.confirmReview') }}
        </Button>
      </div>
    </Modal>
  </section>
</template>
