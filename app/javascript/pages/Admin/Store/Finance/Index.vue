<script setup lang="ts">
import { computed, onMounted, onUnmounted, reactive, ref } from 'vue'
import { Link, router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import {
  Alert,
  Button,
  Card,
  DatePicker,
  Descriptions,
  DescriptionsItem,
  Drawer,
  Empty,
  Form,
  FormItem,
  Grid,
  GridItem,
  Input,
  Message,
  Modal,
  Option,
  PageHeader,
  Pagination,
  Progress,
  Select,
  Space,
  Statistic,
  Table,
  TableColumn,
  Tag,
  Textarea,
  Timeline,
  TimelineItem,
  TypographyText,
} from '@mcweb/ui'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { getJson, HttpError, postJson } from '@/lib/http'

defineOptions({ layout: AdminLayout })

type TaxDimension = {
  rate_bps: number
  code: string
  country: string
  region?: string | null
  pricing_mode: string
  rounding_mode: string
}

type FinanceDocument = {
  id: string
  number: string
  version: number
  kind: 'invoice' | 'refund_receipt'
  status: 'issued' | 'superseded' | 'voided'
  channel: string
  currency: string
  net_cents: number
  tax_cents: number
  gross_cents: number
  issued_at: string
  retention_until: string
  order: {
    id: string
    number: string
    url: string
  }
  refund_id?: number | null
  tax: TaxDimension
  paths: {
    detail: string
    transition: string
  }
}

type FinanceDocumentDetail = FinanceDocument & {
  content: Record<string, unknown>
  supersedes?: string | null
  superseded_by?: string | null
  voided_at?: string | null
  superseded_at?: string | null
  events: Array<{
    type: string
    actor?: string | null
    reason?: string | null
    created_at: string
    metadata: Record<string, unknown>
  }>
}

type FinanceExport = {
  id: string
  status: 'queued' | 'running' | 'completed' | 'failed' | 'expired' | 'revoked'
  progress: number
  format: string
  filters: Record<string, string | number>
  row_count?: number | null
  requested_at: string
  started_at?: string | null
  completed_at?: string | null
  expires_at?: string | null
  error_code?: string | null
  downloadable: boolean
  paths: {
    download: string
    revoke: string
  }
  events: Array<{
    status: string
    progress: number
    created_at: string
  }>
}

type Filters = {
  from?: string
  to?: string
  channel?: string
  currency?: string
  status?: string
  document_kind?: string
  tax_country?: string
  tax_region?: string
  tax_rate_bps?: number
}

const props = defineProps<{
  filters: Filters
  filterOptions: {
    channels: string[]
    currencies: string[]
    tax_countries: string[]
    tax_regions: string[]
    tax_rates: number[]
  }
  summary: {
    documents: number
    invoices: number
    refund_receipts: number
    totals_by_currency: Array<{
      currency: string
      gross_cents: number
      tax_cents: number
    }>
  }
  documents: FinanceDocument[]
  pagination: {
    page: number
    pages: number
    count: number
    limit: number
  }
  exports: FinanceExport[]
  permissions: {
    manageDocuments: boolean
    createExports: boolean
    downloadExports: boolean
  }
  retention: Record<string, { record_days?: number; file_hours?: number; deletion: string }>
  paths: {
    index: string
    createExport: string
  }
}>()

const { t, locale } = useI18n()
const form = reactive({
  from: props.filters.from?.slice(0, 10) || '',
  to: props.filters.to?.slice(0, 10) || '',
  channel: props.filters.channel || '',
  currency: props.filters.currency || '',
  status: props.filters.status || '',
  document_kind: props.filters.document_kind || '',
  tax_country: props.filters.tax_country || '',
  tax_region: props.filters.tax_region || '',
  tax_rate_bps: props.filters.tax_rate_bps ?? '',
})
const selectedDocument = ref<FinanceDocumentDetail | null>(null)
const documentLoading = ref(false)
const exporting = ref(false)
const revokingExportId = ref<string | null>(null)
const transitionTarget = ref<FinanceDocumentDetail | null>(null)
const transitionAction = ref<'revise' | 'void'>('revise')
const transitionReason = ref('')
const transitionRequestId = ref('')
const transitioning = ref(false)
let pollTimer: ReturnType<typeof setInterval> | null = null

const activeFilterCount = computed(() => Object.values(form).filter((value) => value !== '').length)
const hasActiveExports = computed(() => props.exports.some((item) => ['queued', 'running'].includes(item.status)))
const transitionVisible = computed({
  get: () => transitionTarget.value !== null,
  set: (visible: boolean) => {
    if (!visible && !transitioning.value) transitionTarget.value = null
  },
})

function query(page = 1) {
  return Object.fromEntries(
    Object.entries({ ...form, page }).filter(([, value]) => value !== '' && value !== null),
  )
}

function applyFilters() {
  router.get(props.paths.index, query(), {
    preserveState: true,
    preserveScroll: true,
    replace: true,
  })
}

function clearFilters() {
  Object.assign(form, {
    from: '',
    to: '',
    channel: '',
    currency: '',
    status: '',
    document_kind: '',
    tax_country: '',
    tax_region: '',
    tax_rate_bps: '',
  })
  applyFilters()
}

function changePage(page: number) {
  router.get(props.paths.index, query(page), {
    preserveState: true,
    preserveScroll: true,
    replace: true,
  })
}

function formatDate(value?: string | null) {
  if (!value) return t('admin.finance.notAvailable')
  return new Intl.DateTimeFormat(locale.value, {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(value))
}

function formatMoney(cents: number, currency: string) {
  try {
    return new Intl.NumberFormat(locale.value, {
      style: 'currency',
      currency,
    }).format(cents / 100)
  } catch {
    return `${currency} ${(cents / 100).toFixed(2)}`
  }
}

function formatSummaryAmount(kind: 'gross_cents' | 'tax_cents') {
  if (props.summary.totals_by_currency.length === 0) {
    return form.currency ? formatMoney(0, form.currency) : t('admin.finance.notAvailable')
  }

  return props.summary.totals_by_currency
    .map((total) => formatMoney(total[kind], total.currency))
    .join(' · ')
}

function formatRate(rateBps: number) {
  return `${(rateBps / 100).toFixed(2)}%`
}

function statusColor(status: string) {
  if (status === 'issued' || status === 'completed') return 'green'
  if (status === 'failed' || status === 'voided') return 'red'
  if (status === 'expired' || status === 'superseded' || status === 'revoked') return 'gray'
  return 'arcoblue'
}

function errorMessage(error: unknown) {
  if (error instanceof HttpError && error.body && typeof error.body === 'object' && 'error' in error.body) {
    return String((error.body as { error: unknown }).error)
  }
  return t('admin.finance.requestFailed')
}

async function openDocument(document: FinanceDocument) {
  documentLoading.value = true
  selectedDocument.value = null
  try {
    selectedDocument.value = await getJson<FinanceDocumentDetail>(document.paths.detail)
  } catch (error) {
    Message.error(errorMessage(error))
  } finally {
    documentLoading.value = false
  }
}

function openTransition(document: FinanceDocumentDetail, action: 'revise' | 'void') {
  transitionTarget.value = document
  transitionAction.value = action
  transitionReason.value = ''
  transitionRequestId.value = crypto.randomUUID()
}

async function executeTransition() {
  if (!transitionTarget.value) return
  transitioning.value = true
  try {
    const response = await postJson<{ document: FinanceDocumentDetail; replayed: boolean }>(
      transitionTarget.value.paths.transition,
      {
        finance_document: {
          transition_action: transitionAction.value,
          reason: transitionReason.value,
          request_id: transitionRequestId.value,
        },
      },
    )
    selectedDocument.value = response.document
    transitionTarget.value = null
    Message.success(t(`admin.finance.transitions.${transitionAction.value}Success`))
    router.reload({
      only: ['documents', 'summary'],
      preserveScroll: true,
      preserveState: true,
    })
  } catch (error) {
    Message.error(errorMessage(error))
  } finally {
    transitioning.value = false
  }
}

async function requestExport() {
  exporting.value = true
  try {
    await postJson(props.paths.createExport, {
      finance_export: {
        idempotency_key: crypto.randomUUID(),
        filters: Object.fromEntries(
          Object.entries(form).filter(([, value]) => value !== '' && value !== null),
        ),
      },
    })
    Message.success(t('admin.finance.exports.requested'))
    router.reload({
      only: ['exports'],
      preserveState: true,
      preserveScroll: true,
    })
  } catch (error) {
    Message.error(errorMessage(error))
  } finally {
    exporting.value = false
  }
}

async function revokeExport(financeExport: FinanceExport) {
  revokingExportId.value = financeExport.id
  try {
    await postJson(financeExport.paths.revoke)
    Message.success(t('admin.finance.exports.revoked'))
    router.reload({
      only: ['exports'],
      preserveState: true,
      preserveScroll: true,
    })
  } catch (error) {
    Message.error(errorMessage(error))
  } finally {
    revokingExportId.value = null
  }
}

function downloadExport(financeExport: FinanceExport) {
  const anchor = document.createElement('a')
  anchor.href = financeExport.paths.download
  anchor.download = ''
  document.body.appendChild(anchor)
  anchor.click()
  anchor.remove()
}

function pollExports() {
  if (!hasActiveExports.value) return
  router.reload({
    only: ['exports'],
    preserveState: true,
    preserveScroll: true,
  })
}

onMounted(() => {
  pollTimer = setInterval(pollExports, 5_000)
})

onUnmounted(() => {
  if (pollTimer) clearInterval(pollTimer)
})
</script>

<template>
  <PageHeader
    :title="t('admin.finance.title')"
    :subtitle="t('admin.finance.subtitle')"
    :show-back="false"
  >
      <template #extra>
        <Button
          v-if="permissions.createExports"
          type="primary"
          :loading="exporting"
          @click="requestExport"
        >
          {{ t('admin.finance.exports.create') }}
        </Button>
      </template>
  </PageHeader>

  <Space direction="vertical" size="large" fill>
      <Alert type="info" :title="t('admin.finance.retention.title')">
        {{
          t('admin.finance.retention.description', {
            recordDays: retention.invoices?.record_days || 0,
            fileHours: retention.export_files?.file_hours || 0,
          })
        }}
      </Alert>

      <Grid :cols="{ xs: 1, sm: 2, lg: 5 }" :col-gap="16" :row-gap="16">
        <GridItem>
          <Card :bordered="true" hoverable>
            <Statistic :title="t('admin.finance.metrics.documents')" :value="summary.documents" />
          </Card>
        </GridItem>
        <GridItem>
          <Card :bordered="true" hoverable>
            <Statistic :title="t('admin.finance.metrics.invoices')" :value="summary.invoices" />
          </Card>
        </GridItem>
        <GridItem>
          <Card :bordered="true" hoverable>
            <Statistic :title="t('admin.finance.metrics.refundReceipts')" :value="summary.refund_receipts" />
          </Card>
        </GridItem>
        <GridItem>
          <Card :bordered="true" hoverable>
            <Statistic
              :title="t('admin.finance.metrics.gross')"
              :value="formatSummaryAmount('gross_cents')"
            />
          </Card>
        </GridItem>
        <GridItem>
          <Card :bordered="true" hoverable>
            <Statistic
              :title="t('admin.finance.metrics.tax')"
              :value="formatSummaryAmount('tax_cents')"
            />
          </Card>
        </GridItem>
      </Grid>

      <Card :title="t('admin.finance.filters.title')" :bordered="false">
        <Form layout="vertical" @submit.prevent="applyFilters">
          <Grid :cols="{ xs: 1, sm: 2, lg: 4 }" :col-gap="16" :row-gap="4">
            <GridItem>
              <FormItem :label="t('admin.finance.filters.from')">
                <DatePicker v-model="form.from" value-format="YYYY-MM-DD" format="YYYY-MM-DD" allow-clear />
              </FormItem>
            </GridItem>
            <GridItem>
              <FormItem :label="t('admin.finance.filters.to')">
                <DatePicker v-model="form.to" value-format="YYYY-MM-DD" format="YYYY-MM-DD" allow-clear />
              </FormItem>
            </GridItem>
            <GridItem>
              <FormItem :label="t('admin.finance.filters.channel')">
                <Select v-model="form.channel" allow-clear>
                  <Option v-for="channel in filterOptions.channels" :key="channel" :value="channel">
                    {{ channel }}
                  </Option>
                </Select>
              </FormItem>
            </GridItem>
            <GridItem>
              <FormItem :label="t('admin.finance.filters.currency')">
                <Select v-model="form.currency" allow-clear>
                  <Option v-for="currency in filterOptions.currencies" :key="currency" :value="currency">
                    {{ currency }}
                  </Option>
                </Select>
              </FormItem>
            </GridItem>
            <GridItem>
              <FormItem :label="t('admin.finance.filters.status')">
                <Select v-model="form.status" allow-clear>
                  <Option v-for="status in ['issued', 'superseded', 'voided']" :key="status" :value="status">
                    {{ t(`admin.finance.statuses.${status}`) }}
                  </Option>
                </Select>
              </FormItem>
            </GridItem>
            <GridItem>
              <FormItem :label="t('admin.finance.filters.kind')">
                <Select v-model="form.document_kind" allow-clear>
                  <Option value="invoice">{{ t('admin.finance.kinds.invoice') }}</Option>
                  <Option value="refund_receipt">{{ t('admin.finance.kinds.refund_receipt') }}</Option>
                </Select>
              </FormItem>
            </GridItem>
            <GridItem>
              <FormItem :label="t('admin.finance.filters.taxCountry')">
                <Select v-model="form.tax_country" allow-clear allow-search>
                  <Option v-for="country in filterOptions.tax_countries" :key="country" :value="country">
                    {{ country }}
                  </Option>
                </Select>
              </FormItem>
            </GridItem>
            <GridItem>
              <FormItem :label="t('admin.finance.filters.taxRegion')">
                <Select v-model="form.tax_region" allow-clear allow-search>
                  <Option v-for="region in filterOptions.tax_regions" :key="region" :value="region">
                    {{ region }}
                  </Option>
                </Select>
              </FormItem>
            </GridItem>
            <GridItem>
              <FormItem :label="t('admin.finance.filters.taxRate')">
                <Select v-model="form.tax_rate_bps" allow-clear>
                  <Option v-for="rate in filterOptions.tax_rates" :key="rate" :value="rate">
                    {{ formatRate(rate) }}
                  </Option>
                </Select>
              </FormItem>
            </GridItem>
            <GridItem>
              <FormItem hide-label>
                <Space wrap>
                  <Button type="primary" html-type="submit">{{ t('admin.finance.filters.apply') }}</Button>
                  <Button :disabled="activeFilterCount === 0" @click="clearFilters">
                    {{ t('admin.finance.filters.clear') }}
                  </Button>
                </Space>
              </FormItem>
            </GridItem>
          </Grid>
        </Form>
      </Card>

      <Card :title="t('admin.finance.documents.title')" :bordered="false">
        <Empty v-if="documents.length === 0" :description="t('admin.finance.documents.empty')" />
        <template v-else>
          <Grid :cols="24" :row-gap="12">
            <GridItem :span="{ xs: 0, md: 24 }">
              <Table :data="documents" :pagination="false" row-key="id" :scroll="{ x: 1180 }">
              <TableColumn :title="t('admin.finance.columns.document')" :width="220">
                <template #cell="{ record }">
                  <Button type="text" @click="openDocument(record)">
                    {{ record.number }}
                  </Button>
                  <TypographyText type="secondary">v{{ record.version }}</TypographyText>
                </template>
              </TableColumn>
              <TableColumn :title="t('admin.finance.columns.kind')" :width="150">
                <template #cell="{ record }">
                  <Tag :color="record.kind === 'invoice' ? 'arcoblue' : 'orange'">
                    {{ t(`admin.finance.kinds.${record.kind}`) }}
                  </Tag>
                </template>
              </TableColumn>
              <TableColumn :title="t('admin.finance.columns.order')" :width="190">
                <template #cell="{ record }">
                  <Link :href="record.order.url">{{ record.order.number }}</Link>
                </template>
              </TableColumn>
              <TableColumn :title="t('admin.finance.columns.channel')" data-index="channel" :width="130" />
              <TableColumn :title="t('admin.finance.columns.amount')" :width="170">
                <template #cell="{ record }">
                  {{ formatMoney(record.gross_cents, record.currency) }}
                </template>
              </TableColumn>
              <TableColumn :title="t('admin.finance.columns.tax')" :width="180">
                <template #cell="{ record }">
                  <Space direction="vertical" size="mini">
                    <TypographyText>{{ formatMoney(record.tax_cents, record.currency) }}</TypographyText>
                    <TypographyText type="secondary">
                      {{ formatRate(record.tax.rate_bps) }} · {{ record.tax.country }} {{ record.tax.region || '' }}
                    </TypographyText>
                  </Space>
                </template>
              </TableColumn>
              <TableColumn :title="t('admin.finance.columns.status')" :width="130">
                <template #cell="{ record }">
                  <Tag :color="statusColor(record.status)">{{ t(`admin.finance.statuses.${record.status}`) }}</Tag>
                </template>
              </TableColumn>
              <TableColumn :title="t('admin.finance.columns.issuedAt')" :width="190">
                <template #cell="{ record }">{{ formatDate(record.issued_at) }}</template>
              </TableColumn>
              </Table>
            </GridItem>

            <GridItem :span="{ xs: 24, md: 0 }">
              <Grid :cols="1" :row-gap="12">
                <GridItem v-for="record in documents" :key="record.id">
                  <Card :bordered="true">
                    <Space direction="vertical" fill>
                      <Space justify="space-between" fill wrap>
                        <Button type="text" @click="openDocument(record)">{{ record.number }}</Button>
                        <Tag :color="statusColor(record.status)">{{ t(`admin.finance.statuses.${record.status}`) }}</Tag>
                      </Space>
                      <TypographyText type="secondary">
                        {{ t(`admin.finance.kinds.${record.kind}`) }} · v{{ record.version }} · {{ record.order.number }}
                      </TypographyText>
                      <TypographyText bold>{{ formatMoney(record.gross_cents, record.currency) }}</TypographyText>
                      <TypographyText>
                        {{ t('admin.finance.columns.tax') }}:
                        {{ formatMoney(record.tax_cents, record.currency) }} · {{ formatRate(record.tax.rate_bps) }}
                      </TypographyText>
                      <TypographyText type="secondary">{{ formatDate(record.issued_at) }}</TypographyText>
                    </Space>
                  </Card>
                </GridItem>
              </Grid>
            </GridItem>
          </Grid>

          <Space v-if="pagination.pages > 1" justify="end" fill>
            <Pagination
              :current="pagination.page"
              :total="pagination.count"
              :page-size="pagination.limit"
              show-total
              @change="changePage"
            />
          </Space>
        </template>
      </Card>

      <Card :title="t('admin.finance.exports.title')" :bordered="false">
        <Empty v-if="exports.length === 0" :description="t('admin.finance.exports.empty')" />
        <Grid v-else :cols="{ xs: 1, md: 2, xl: 3 }" :col-gap="16" :row-gap="16">
          <GridItem v-for="financeExport in exports" :key="financeExport.id">
            <Card :bordered="true">
              <Space direction="vertical" fill>
              <Space justify="space-between" fill>
                <TypographyText bold>{{ t('admin.finance.exports.item', { id: financeExport.id }) }}</TypographyText>
                <Tag :color="statusColor(financeExport.status)">
                  {{ t(`admin.finance.exportStatuses.${financeExport.status}`) }}
                </Tag>
              </Space>
              <Progress
                :percent="financeExport.progress / 100"
                :status="financeExport.status === 'failed' ? 'danger' : 'normal'"
              />
              <TypographyText type="secondary">
                {{ t('admin.finance.exports.requestedAt', { time: formatDate(financeExport.requested_at) }) }}
              </TypographyText>
              <TypographyText v-if="financeExport.row_count !== null && financeExport.row_count !== undefined">
                {{ t('admin.finance.exports.rows', { count: financeExport.row_count }) }}
              </TypographyText>
              <TypographyText v-if="financeExport.expires_at" type="warning">
                {{ t('admin.finance.exports.expiresAt', { time: formatDate(financeExport.expires_at) }) }}
              </TypographyText>
              <TypographyText v-if="financeExport.error_code" type="danger">
                {{ t('admin.finance.exports.failed') }}
              </TypographyText>
              <Space wrap>
                <Button
                  v-if="financeExport.downloadable && permissions.downloadExports"
                  type="primary"
                  size="small"
                  @click="downloadExport(financeExport)"
                >
                  {{ t('admin.finance.exports.download') }}
                </Button>
                <Button
                  v-if="permissions.createExports && !['expired', 'revoked'].includes(financeExport.status)"
                  status="danger"
                  size="small"
                  :loading="revokingExportId === financeExport.id"
                  @click="revokeExport(financeExport)"
                >
                  {{ t('admin.finance.exports.revoke') }}
                </Button>
              </Space>
              </Space>
            </Card>
          </GridItem>
        </Grid>
      </Card>
  </Space>

    <Drawer
      :visible="documentLoading || Boolean(selectedDocument)"
      :width="'min(680px, calc(100vw - 24px))'"
      :title="t('admin.finance.documents.detailTitle')"
      unmount-on-close
      @cancel="selectedDocument = null"
    >
      <Alert v-if="documentLoading" type="info">{{ t('admin.finance.documents.loading') }}</Alert>
      <template v-else-if="selectedDocument">
        <Space direction="vertical" size="large" fill>
          <Descriptions :column="1" bordered size="small">
            <DescriptionsItem :label="t('admin.finance.columns.document')">
              {{ selectedDocument.number }} · v{{ selectedDocument.version }}
            </DescriptionsItem>
            <DescriptionsItem :label="t('admin.finance.columns.kind')">
              {{ t(`admin.finance.kinds.${selectedDocument.kind}`) }}
            </DescriptionsItem>
            <DescriptionsItem :label="t('admin.finance.columns.status')">
              <Tag :color="statusColor(selectedDocument.status)">
                {{ t(`admin.finance.statuses.${selectedDocument.status}`) }}
              </Tag>
            </DescriptionsItem>
            <DescriptionsItem :label="t('admin.finance.columns.order')">
              <Link :href="selectedDocument.order.url">{{ selectedDocument.order.number }}</Link>
            </DescriptionsItem>
            <DescriptionsItem :label="t('admin.finance.columns.net')">
              {{ formatMoney(selectedDocument.net_cents, selectedDocument.currency) }}
            </DescriptionsItem>
            <DescriptionsItem :label="t('admin.finance.columns.tax')">
              {{ formatMoney(selectedDocument.tax_cents, selectedDocument.currency) }}
            </DescriptionsItem>
            <DescriptionsItem :label="t('admin.finance.columns.amount')">
              {{ formatMoney(selectedDocument.gross_cents, selectedDocument.currency) }}
            </DescriptionsItem>
            <DescriptionsItem :label="t('admin.finance.documents.taxDimension')">
              {{ formatRate(selectedDocument.tax.rate_bps) }} · {{ selectedDocument.tax.code }} ·
              {{ selectedDocument.tax.country }} {{ selectedDocument.tax.region || '' }} ·
              {{ t(`admin.finance.rounding.${selectedDocument.tax.rounding_mode}`) }}
            </DescriptionsItem>
            <DescriptionsItem :label="t('admin.finance.documents.retainedUntil')">
              {{ formatDate(selectedDocument.retention_until) }}
            </DescriptionsItem>
          </Descriptions>

          <Alert type="warning" :title="t('admin.finance.documents.immutableTitle')">
            {{ t('admin.finance.documents.immutableDescription') }}
          </Alert>

          <Space v-if="permissions.manageDocuments && selectedDocument.status === 'issued'" wrap>
            <Button type="primary" @click="openTransition(selectedDocument, 'revise')">
              {{ t('admin.finance.transitions.revise') }}
            </Button>
            <Button status="danger" @click="openTransition(selectedDocument, 'void')">
              {{ t('admin.finance.transitions.void') }}
            </Button>
          </Space>

          <Card :title="t('admin.finance.documents.timeline')" :bordered="false">
            <Timeline v-if="selectedDocument.events.length">
              <TimelineItem v-for="event in selectedDocument.events" :key="`${event.type}-${event.created_at}`">
                <Space direction="vertical" size="mini">
                  <TypographyText bold>{{ t(`admin.finance.events.${event.type}`) }}</TypographyText>
                  <TypographyText type="secondary">
                    {{ event.actor || t('admin.finance.systemActor') }} · {{ formatDate(event.created_at) }}
                  </TypographyText>
                  <TypographyText v-if="event.reason">{{ event.reason }}</TypographyText>
                </Space>
              </TimelineItem>
            </Timeline>
            <Empty v-else :description="t('admin.finance.notAvailable')" />
          </Card>
        </Space>
      </template>
    </Drawer>

    <Modal
      v-model:visible="transitionVisible"
      :title="t(`admin.finance.transitions.${transitionAction}Title`)"
      :ok-text="t(`admin.finance.transitions.${transitionAction}`)"
      :cancel-text="t('common.cancel')"
      :ok-loading="transitioning"
      :ok-button-props="{ status: transitionAction === 'void' ? 'danger' : 'normal' }"
      :mask-closable="false"
      :closable="!transitioning"
      unmount-on-close
      @ok="executeTransition"
    >
      <Alert type="warning" :title="t('admin.finance.transitions.warningTitle')">
        {{ t('admin.finance.transitions.warningDescription') }}
      </Alert>
      <Form layout="vertical">
        <FormItem :label="t('admin.finance.transitions.reason')" required>
          <Textarea
            v-model="transitionReason"
            :max-length="1000"
            show-word-limit
            :placeholder="t('admin.finance.transitions.reasonPlaceholder')"
          />
        </FormItem>
        <FormItem :label="t('admin.finance.transitions.requestId')">
          <Input v-model="transitionRequestId" readonly />
        </FormItem>
      </Form>
  </Modal>
</template>
