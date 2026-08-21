<script setup lang="ts">
import { computed, reactive, ref, watch } from 'vue'
import { Link, router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import {
  Alert,
  Button,
  Card,
  Empty,
  Form,
  FormItem,
  Input,
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
  Tag,
  Textarea,
  TypographyText,
} from '@mcweb/ui'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { adminRoutes } from '@/lib/adminRoutes'

defineOptions({ layout: AdminLayout })

type LatePaymentAction = {
  url: string
  token: string
}

type LatePaymentRow = {
  id: number
  order_id: string
  order_number: string
  provider: string
  payment_reference: string | null
  webhook_reference: string | null
  webhook_event_type: string
  status: 'open' | 'acknowledged'
  reason:
    | 'order_cancelled'
    | 'order_expired'
    | 'order_already_paid'
    | 'order_not_payable'
    | 'payment_superseded'
  amount_cents: number
  currency: string
  disposition?: string | null
  review_note?: string | null
  acknowledged_by?: string | null
  acknowledged_at?: string | null
  created_at: string
  updated_at: string
  action?: LatePaymentAction
}

type PaginationMeta = {
  page: number
  pages: number
  count: number
  from: number | null
  to: number | null
}

const props = defineProps<{
  filters: {
    status: string | null
    reason: string | null
    provider: string | null
    q: string | null
  }
  filterOptions: {
    statuses: string[]
    reasons: string[]
    providers: string[]
  }
  summary: {
    total: number
    open: number
    acknowledged: number
  }
  dispositions: string[]
  rows: LatePaymentRow[]
  pagination: PaginationMeta
}>()

const { locale, t, te } = useI18n()
const status = ref(props.filters.status || '')
const reason = ref(props.filters.reason || '')
const provider = ref(props.filters.provider || '')
const query = ref(props.filters.q || '')
const selectedCase = ref<LatePaymentRow | null>(null)
const submitting = ref(false)
const reviewForm = reactive({
  disposition: '',
  note: '',
  confirmation: '',
})

const modalVisible = computed({
  get: () => selectedCase.value !== null,
  set: (visible: boolean) => {
    if (!visible) closeReview()
  },
})

const canSubmit = computed(() => {
  const selected = selectedCase.value
  const noteLength = reviewForm.note.trim().length
  return Boolean(
    selected?.action &&
      props.dispositions.includes(reviewForm.disposition) &&
      noteLength >= 10 &&
      noteLength <= 1000 &&
      reviewForm.confirmation.trim() === selected.order_number,
  )
})

watch(
  () => props.filters,
  (filters) => {
    status.value = filters.status || ''
    reason.value = filters.reason || ''
    provider.value = filters.provider || ''
    query.value = filters.q || ''
  },
)

function translation(path: string, fallback: string) {
  return te(path) ? t(path) : fallback
}

function statusLabel(value: string) {
  return translation(`admin.latePayments.statuses.${value}`, value)
}

function reasonLabel(value: string) {
  return translation(`admin.latePayments.reasons.${value}`, value)
}

function dispositionLabel(value: string | null | undefined) {
  if (!value) return t('admin.latePayments.notReviewed')
  return translation(`admin.latePayments.dispositions.${value}`, value)
}

function formatMoney(row: LatePaymentRow) {
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

function visit(patch: Record<string, string | number | undefined>) {
  const next: Record<string, string | number> = {
    ...(status.value ? { status: status.value } : {}),
    ...(reason.value ? { reason: reason.value } : {}),
    ...(provider.value ? { provider: provider.value } : {}),
    ...(query.value ? { q: query.value } : {}),
  }

  Object.entries(patch).forEach(([key, value]) => {
    if (value === undefined || value === '') delete next[key]
    else next[key] = value
  })

  router.get(adminRoutes.storeLatePaymentCases, next, {
    preserveScroll: true,
    preserveState: true,
    replace: true,
  })
}

function openReview(reviewCase: LatePaymentRow) {
  if (!reviewCase.action) return
  selectedCase.value = reviewCase
  reviewForm.disposition = ''
  reviewForm.note = ''
  reviewForm.confirmation = ''
}

function closeReview() {
  if (submitting.value) return
  selectedCase.value = null
  reviewForm.disposition = ''
  reviewForm.note = ''
  reviewForm.confirmation = ''
}

function submitReview() {
  const selected = selectedCase.value
  if (!selected?.action || !canSubmit.value) return

  router.patch(
    selected.action.url,
    {
      token: selected.action.token,
      disposition: reviewForm.disposition,
      note: reviewForm.note.trim(),
      confirmation: reviewForm.confirmation.trim(),
    },
    {
      preserveScroll: true,
      onStart: () => {
        submitting.value = true
      },
      onSuccess: () => {
        selectedCase.value = null
      },
      onFinish: () => {
        submitting.value = false
      },
    },
  )
}
</script>

<template>
  <section>
    <PageHeader
      :title="t('admin.latePayments.title')"
      :subtitle="t('admin.latePayments.subtitle')"
      :show-back="false"
      class="mb-4 !px-0"
    >
      <template #extra>
        <Button @click="router.visit(adminRoutes.storePaymentOperations)">
          {{ t('admin.latePayments.backToOperations') }}
        </Button>
      </template>
    </PageHeader>

    <Alert
      type="warning"
      show-icon
      :closable="false"
      :title="t('admin.latePayments.safetyNotice')"
      class="mb-4"
    />

    <div class="mb-4 grid gap-3 sm:grid-cols-3">
      <Card :bordered="false" class="bg-[var(--color-fill-1)]">
        <Statistic :title="t('admin.latePayments.total')" :value="summary.total" />
      </Card>
      <Card :bordered="false" class="bg-[var(--color-fill-1)]">
        <Statistic :title="t('admin.latePayments.open')" :value="summary.open" />
      </Card>
      <Card :bordered="false" class="bg-[var(--color-fill-1)]">
        <Statistic :title="t('admin.latePayments.acknowledged')" :value="summary.acknowledged" />
      </Card>
    </div>

    <Card :bordered="false">
      <div class="mb-5 flex flex-wrap items-center gap-3">
        <Select
          v-model="status"
          allow-clear
          :placeholder="t('admin.latePayments.allStatuses')"
          class="w-full sm:w-44"
          @change="visit({ status: status || undefined })"
          @clear="visit({ status: undefined })"
        >
          <Option v-for="item in filterOptions.statuses" :key="item" :value="item">
            {{ statusLabel(item) }}
          </Option>
        </Select>

        <Select
          v-model="reason"
          allow-clear
          :placeholder="t('admin.latePayments.allReasons')"
          class="w-full sm:w-52"
          @change="visit({ reason: reason || undefined })"
          @clear="visit({ reason: undefined })"
        >
          <Option v-for="item in filterOptions.reasons" :key="item" :value="item">
            {{ reasonLabel(item) }}
          </Option>
        </Select>

        <Select
          v-model="provider"
          allow-clear
          :placeholder="t('admin.latePayments.allProviders')"
          class="w-full sm:w-44"
          @change="visit({ provider: provider || undefined })"
          @clear="visit({ provider: undefined })"
        >
          <Option v-for="item in filterOptions.providers" :key="item" :value="item">
            {{ item }}
          </Option>
        </Select>

        <InputSearch
          v-model="query"
          allow-clear
          search-button
          :placeholder="t('admin.latePayments.searchPlaceholder')"
          class="min-w-0 flex-1 basis-full sm:min-w-64 sm:basis-64"
          @search="visit({ q: query || undefined })"
          @clear="visit({ q: undefined })"
        />
      </div>

      <div class="overflow-x-auto">
        <Table
          :data="rows"
          :pagination="false"
          row-key="id"
          :bordered="{ wrapper: true, cell: false }"
          :scroll="{ x: 1540 }"
          stripe
        >
          <template #columns>
            <TableColumn :title="t('admin.latePayments.order')" data-index="order_number" :width="180">
              <template #cell="{ record }">
                <Link
                  :href="adminRoutes.storeOrder(record.order_id)"
                  class="arco-link font-medium no-underline"
                >
                  {{ record.order_number }}
                </Link>
              </template>
            </TableColumn>

            <TableColumn :title="t('admin.latePayments.provider')" :width="190">
              <template #cell="{ record }">
                <div class="min-w-0 space-y-1">
                  <Tag color="arcoblue">{{ record.provider }}</Tag>
                  <p
                    class="truncate text-xs text-[var(--color-text-3)]"
                    :title="record.payment_reference || undefined"
                  >
                    {{ record.payment_reference || '—' }}
                  </p>
                </div>
              </template>
            </TableColumn>

            <TableColumn :title="t('admin.latePayments.event')" :width="260">
              <template #cell="{ record }">
                <div class="min-w-0 space-y-1">
                  <p class="truncate font-medium" :title="record.webhook_event_type">
                    {{ record.webhook_event_type }}
                  </p>
                  <p
                    class="truncate text-xs text-[var(--color-text-3)]"
                    :title="record.webhook_reference || undefined"
                  >
                    {{ record.webhook_reference || '—' }}
                  </p>
                </div>
              </template>
            </TableColumn>

            <TableColumn :title="t('admin.latePayments.reason')" :width="180">
              <template #cell="{ record }">
                <Space direction="vertical" size="mini">
                  <Tag :color="record.status === 'open' ? 'orange' : 'green'">
                    {{ statusLabel(record.status) }}
                  </Tag>
                  <TypographyText type="secondary">
                    {{ reasonLabel(record.reason) }}
                  </TypographyText>
                </Space>
              </template>
            </TableColumn>

            <TableColumn :title="t('admin.latePayments.amount')" :width="140" align="right">
              <template #cell="{ record }">
                <strong>{{ formatMoney(record) }}</strong>
              </template>
            </TableColumn>

            <TableColumn :title="t('admin.latePayments.createdAt')" :width="190">
              <template #cell="{ record }">{{ formatTime(record.created_at) }}</template>
            </TableColumn>

            <TableColumn :title="t('admin.latePayments.review')" :width="260">
              <template #cell="{ record }">
                <div v-if="record.status === 'acknowledged'" class="space-y-1">
                  <p class="font-medium">{{ dispositionLabel(record.disposition) }}</p>
                  <p class="text-xs text-[var(--color-text-3)]">
                    {{ t('admin.latePayments.reviewedBy', {
                      user: record.acknowledged_by,
                      time: formatTime(record.acknowledged_at),
                    }) }}
                  </p>
                  <p v-if="record.review_note" class="line-clamp-2 text-sm text-[var(--color-text-2)]">
                    {{ record.review_note }}
                  </p>
                </div>
                <TypographyText v-else type="secondary">
                  {{ t('admin.latePayments.notReviewed') }}
                </TypographyText>
              </template>
            </TableColumn>

            <TableColumn :title="t('admin.latePayments.actions')" :width="140" fixed="right">
              <template #cell="{ record }">
                <Button
                  v-if="record.action"
                  type="outline"
                  status="warning"
                  size="small"
                  @click="openReview(record)"
                >
                  {{ t('admin.latePayments.acknowledge') }}
                </Button>
              </template>
            </TableColumn>
          </template>

          <template #empty>
            <Empty :description="t('admin.latePayments.empty')" />
          </template>
        </Table>
      </div>

      <div class="mt-5 flex flex-wrap items-center justify-between gap-3">
        <TypographyText type="secondary">
          {{ t('admin.latePayments.range', {
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
      v-model:visible="modalVisible"
      :title="t('admin.latePayments.acknowledgeTitle')"
      :footer="false"
      :mask-closable="!submitting"
      :esc-to-close="!submitting"
      :width="'min(600px, calc(100vw - 32px))'"
    >
      <Alert
        type="warning"
        show-icon
        :closable="false"
        :title="t('admin.latePayments.acknowledgeWarning')"
        class="mb-5"
      />

      <Form :model="reviewForm" layout="vertical">
        <FormItem field="disposition" :label="t('admin.latePayments.disposition')" required>
          <Select
            v-model="reviewForm.disposition"
            :placeholder="t('admin.latePayments.dispositionPlaceholder')"
            :disabled="submitting"
          >
            <Option v-for="item in dispositions" :key="item" :value="item">
              {{ dispositionLabel(item) }}
            </Option>
          </Select>
        </FormItem>

        <FormItem field="note" :label="t('admin.latePayments.note')" required>
          <Textarea
            v-model="reviewForm.note"
            :placeholder="t('admin.latePayments.notePlaceholder')"
            :max-length="1000"
            show-word-limit
            :auto-size="{ minRows: 4, maxRows: 8 }"
            :disabled="submitting"
          />
          <template #extra>{{ t('admin.latePayments.noteHelp') }}</template>
        </FormItem>

        <FormItem field="confirmation" :label="t('admin.latePayments.confirmation')" required>
          <Input
            v-model="reviewForm.confirmation"
            :placeholder="t('admin.latePayments.confirmationPlaceholder', {
              order: selectedCase?.order_number,
            })"
            :disabled="submitting"
            autocomplete="off"
          />
          <template #extra>{{ t('admin.latePayments.confirmationHelp') }}</template>
        </FormItem>
      </Form>

      <div class="flex flex-wrap justify-end gap-2 pt-2">
        <Button :disabled="submitting" @click="closeReview">
          {{ t('admin.latePayments.cancel') }}
        </Button>
        <Button
          type="primary"
          status="danger"
          :loading="submitting"
          :disabled="!canSubmit"
          @click="submitReview"
        >
          {{ t('admin.latePayments.confirmAcknowledge') }}
        </Button>
      </div>
    </Modal>
  </section>
</template>
