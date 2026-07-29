<script setup lang="ts">
import { computed, reactive, ref } from 'vue'
import { Link, router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import {
  Alert,
  Button,
  Card,
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
  Spin,
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
import HighRiskActionModal from '@/components/admin/HighRiskActionModal.vue'
import { createIdempotencyKey } from '@/lib/idempotency'
import { adminRoutes } from '@/lib/adminRoutes'
import { getJson, HttpError, postJson } from '@/lib/http'

defineOptions({ layout: AdminLayout })

type OptionRow = { value: string; label: string }
type Permissions = {
  sensitiveRead: boolean
  assign: boolean
  note: boolean
  evidenceSubmit: boolean
  acceptLoss: boolean
  close: boolean
  rightsManage: boolean
}
type DisputeRow = {
  publicId: string
  status: string
  statusLabel: string
  riskLevel: string
  riskLabel: string
  orderNumber: string
  provider: string
  amount: string
  liability: string
  evidenceDueAt?: string | null
  overdue: boolean
  assignee?: string | null
  rightsStatus: string
  detailUrl: string
}
type DisputeDetail = {
  dispute: DisputeRow & {
    lockVersion: number
    kind: string
    providerStatus: string
    reason: string
    offset: string
    resolution?: string | null
    resolutionLabel?: string | null
    rightsStatusLabel: string
    createdAt: string
    closedAt?: string | null
    retentionUntil?: string | null
    retentionBlockers: string[]
    legalHold: boolean
    orderUrl: string
    sensitive?: {
      providerDisputeId: string
      paymentReference?: string | null
      paymentAmount: string
    } | null
  }
  events: Array<{
    id: number
    type: string
    typeLabel: string
    source: string
    sourceLabel: string
    fromStatus?: string | null
    toStatus?: string | null
    toStatusLabel: string
    actor?: string | null
    note?: string | null
    stale: boolean
    createdAt: string
  }>
  evidence: Array<{
    publicId: string
    title: string
    filename: string
    byteSize: number
    sha256?: string | null
    status: string
    statusLabel: string
    submittedBy: string
    submittedAt: string
    retentionUntil?: string | null
    purgedAt?: string | null
    downloadTokenUrl?: string | null
  }>
  permissions: Permissions
  paths: {
    authorizeAction: string
    executeAction: string
  }
}

const props = defineProps<{
  summary: {
    total: number
    active: number
    dueSoon: number
    overdue: number
    liabilityCents: number
  }
  filters: Partial<{
    q: string
    status: string
    provider: string
    risk: string
    assignee: string
    due: string
  }>
  filterOptions: {
    statuses: OptionRow[]
    providers: OptionRow[]
    risks: OptionRow[]
  }
  rows: DisputeRow[]
  pagination: {
    page: number
    pages: number
    count: number
    limit: number
  }
  assignees: OptionRow[]
  permissions: Permissions
}>()

const { locale, t } = useI18n()
const filters = reactive({
  q: props.filters.q || '',
  status: props.filters.status || '',
  provider: props.filters.provider || '',
  risk: props.filters.risk || '',
  assignee: props.filters.assignee || '',
  due: props.filters.due || '',
})
const drawerVisible = ref(false)
const drawerLoading = ref(false)
const detail = ref<DisputeDetail | null>(null)
const detailError = ref('')
const actionVisible = ref(false)
const simpleAction = ref('')
const actionReason = ref('')
const actionNote = ref('')
const assigneeId = ref('')
const evidenceTitle = ref('')
const evidenceFilename = ref('evidence.txt')
const evidenceContent = ref('')
const actionSubmitting = ref(false)
const highRiskVisible = ref(false)
const highRiskAction = ref('')
const downloadingId = ref('')

const dueProgress = computed(() => {
  const current = detail.value?.dispute
  if (!current?.evidenceDueAt) return 0
  const start = new Date(current.createdAt).getTime()
  const end = new Date(current.evidenceDueAt).getTime()
  if (end <= start) return 1
  return Math.min(1, Math.max(0, (Date.now() - start) / (end - start)))
})

const highRiskTitle = computed(() =>
  t(`admin.disputes.actions.${highRiskAction.value}`),
)

function applyFilters(page = 1) {
  const query = Object.fromEntries(
    Object.entries({ ...filters, page }).filter(([, value]) => String(value).length > 0),
  )
  router.get(adminRoutes.storeDisputes, query, {
    preserveState: true,
    preserveScroll: true,
    replace: true,
  })
}

function clearFilters() {
  Object.assign(filters, {
    q: '',
    status: '',
    provider: '',
    risk: '',
    assignee: '',
    due: '',
  })
  applyFilters()
}

async function openDetail(row: DisputeRow) {
  drawerVisible.value = true
  drawerLoading.value = true
  detailError.value = ''
  detail.value = null
  try {
    detail.value = await getJson<DisputeDetail>(row.detailUrl)
  } catch (error) {
    detailError.value = errorMessage(error)
  } finally {
    drawerLoading.value = false
  }
}

async function refreshDetail() {
  const current = detail.value?.dispute
  if (!current) return
  await openDetail(current)
}

function openAction(action: string) {
  simpleAction.value = action
  actionReason.value = ''
  actionNote.value = ''
  assigneeId.value = ''
  evidenceTitle.value = ''
  evidenceFilename.value = 'evidence.txt'
  evidenceContent.value = ''
  actionVisible.value = true
}

function openHighRisk(action: string) {
  highRiskAction.value = action
  highRiskVisible.value = true
}

async function submitSimpleAction() {
  const current = detail.value
  if (!current || !actionReason.value.trim()) return

  actionSubmitting.value = true
  try {
    const payload: Record<string, unknown> = {
      action: simpleAction.value,
      request_id: createIdempotencyKey(),
      reason: actionReason.value.trim(),
      expected_lock_version: current.dispute.lockVersion,
    }
    if (simpleAction.value === 'assign') payload.assignee_id = assigneeId.value
    if (simpleAction.value === 'note') payload.note = actionNote.value.trim()
    if (simpleAction.value === 'submit_evidence') {
      payload.evidence = {
        title: evidenceTitle.value.trim(),
        filename: evidenceFilename.value.trim(),
        content_type: 'text/plain',
        content: evidenceContent.value,
      }
    }

    const result = await postJson<{ message?: string }>(
      current.paths.executeAction,
      payload,
    )
    Message.success(result.message || t('admin.disputes.actionCompleted'))
    actionVisible.value = false
    await refreshDetail()
    router.reload({ only: ['summary', 'rows'] })
  } catch (error) {
    Message.error(errorMessage(error))
  } finally {
    actionSubmitting.value = false
  }
}

async function downloadEvidence(item: DisputeDetail['evidence'][number]) {
  if (!item.downloadTokenUrl) return
  downloadingId.value = item.publicId
  try {
    const result = await postJson<{ url: string; expires_in: number }>(
      item.downloadTokenUrl,
      {},
    )
    const anchor = document.createElement('a')
    anchor.href = result.url
    anchor.download = item.filename
    anchor.rel = 'noopener'
    document.body.appendChild(anchor)
    anchor.click()
    anchor.remove()
  } catch (error) {
    Message.error(errorMessage(error))
  } finally {
    downloadingId.value = ''
  }
}

function actionPayload() {
  return {
    action: highRiskAction.value,
    expected_lock_version: detail.value?.dispute.lockVersion,
  }
}

async function highRiskCompleted() {
  await refreshDetail()
  router.reload({ only: ['summary', 'rows'] })
}

function errorMessage(error: unknown) {
  if (error instanceof HttpError && error.body && typeof error.body === 'object') {
    const message = (error.body as { error?: unknown }).error
    if (typeof message === 'string' && message.length > 0) return message
  }
  return t('admin.disputes.requestFailed')
}

function formatDate(value?: string | null) {
  if (!value) return t('common.notAvailable')
  return new Intl.DateTimeFormat(locale.value, {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(value))
}

function formatBytes(bytes: number) {
  return new Intl.NumberFormat(locale.value, {
    style: 'unit',
    unit: bytes >= 1024 ? 'kilobyte' : 'byte',
    maximumFractionDigits: bytes >= 1024 ? 1 : 0,
  }).format(bytes >= 1024 ? bytes / 1024 : bytes)
}

function statusColor(status: string) {
  if (status === 'won' || status === 'withdrawn') return 'green'
  if (status === 'lost') return 'red'
  if (status === 'under_review' || status === 'evidence_submitted') return 'arcoblue'
  if (status === 'closed') return 'gray'
  return 'orange'
}

function riskColor(risk: string) {
  if (risk === 'critical') return 'red'
  if (risk === 'high') return 'orangered'
  if (risk === 'medium') return 'orange'
  return 'blue'
}

function rightsColor(status: string) {
  if (status === 'revoked') return 'red'
  if (status === 'frozen') return 'orange'
  if (status === 'restored') return 'green'
  return 'gray'
}
</script>

<template>
  <PageHeader
    :title="t('admin.disputes.title')"
    :subtitle="t('admin.disputes.subtitle')"
  />

  <Space direction="vertical" size="large" fill>
    <Alert
      v-if="summary.overdue > 0"
      type="error"
      show-icon
      :title="t('admin.disputes.overdueTitle', { count: summary.overdue })"
    >
      {{ t('admin.disputes.overdueDescription') }}
    </Alert>

    <Grid :cols="{ xs: 1, sm: 2, lg: 5 }" :col-gap="16" :row-gap="16">
      <GridItem>
        <Card class="risk-summary-card" :bordered="false">
          <Statistic :title="t('admin.disputes.metrics.total')" :value="summary.total" />
        </Card>
      </GridItem>
      <GridItem>
        <Card class="risk-summary-card" :bordered="false">
          <Statistic :title="t('admin.disputes.metrics.active')" :value="summary.active" />
        </Card>
      </GridItem>
      <GridItem>
        <Card class="risk-summary-card" :bordered="false">
          <Statistic :title="t('admin.disputes.metrics.dueSoon')" :value="summary.dueSoon" />
        </Card>
      </GridItem>
      <GridItem>
        <Card class="risk-summary-card" :bordered="false">
          <Statistic :title="t('admin.disputes.metrics.overdue')" :value="summary.overdue" />
        </Card>
      </GridItem>
      <GridItem>
        <Card class="risk-summary-card" :bordered="false">
          <Statistic
            :title="t('admin.disputes.metrics.liability')"
            :value="summary.liabilityCents / 100"
            :precision="2"
          />
        </Card>
      </GridItem>
    </Grid>

    <Card class="risk-workbench" :title="t('admin.disputes.queueTitle')" :bordered="false">
      <div class="mb-4 grid gap-3 md:grid-cols-2 xl:grid-cols-6">
        <Input
          v-model="filters.q"
          allow-clear
          :placeholder="t('admin.disputes.filters.search')"
          @press-enter="applyFilters()"
        />
        <Select v-model="filters.status" allow-clear :placeholder="t('admin.disputes.filters.status')">
          <Option v-for="option in filterOptions.statuses" :key="option.value" :value="option.value">
            {{ option.label }}
          </Option>
        </Select>
        <Select v-model="filters.provider" allow-clear :placeholder="t('admin.disputes.filters.provider')">
          <Option v-for="option in filterOptions.providers" :key="option.value" :value="option.value">
            {{ option.label }}
          </Option>
        </Select>
        <Select v-model="filters.risk" allow-clear :placeholder="t('admin.disputes.filters.risk')">
          <Option v-for="option in filterOptions.risks" :key="option.value" :value="option.value">
            {{ option.label }}
          </Option>
        </Select>
        <Select v-model="filters.assignee" allow-clear :placeholder="t('admin.disputes.filters.assignee')">
          <Option value="unassigned">{{ t('admin.disputes.unassigned') }}</Option>
          <Option v-for="option in assignees" :key="option.value" :value="option.value">
            {{ option.label }}
          </Option>
        </Select>
        <Select v-model="filters.due" allow-clear :placeholder="t('admin.disputes.filters.due')">
          <Option value="soon">{{ t('admin.disputes.dueSoon') }}</Option>
          <Option value="overdue">{{ t('admin.disputes.overdue') }}</Option>
        </Select>
      </div>

      <div class="mb-4 flex flex-wrap justify-end gap-2">
        <Button @click="clearFilters">{{ t('common.reset') }}</Button>
        <Button type="primary" @click="applyFilters()">{{ t('common.apply') }}</Button>
      </div>

      <Empty v-if="rows.length === 0" :description="t('admin.disputes.empty')" />
      <Table
        v-else
        class="risk-table"
        :data="rows"
        :pagination="false"
        row-key="publicId"
        :scroll="{ x: 1320 }"
        @row-click="openDetail"
      >
        <TableColumn :title="t('admin.disputes.columns.case')" :width="180">
          <template #cell="{ record }">
            <Button type="text" @click.stop="openDetail(record)">
              {{ record.publicId }}
            </Button>
          </template>
        </TableColumn>
        <TableColumn :title="t('admin.disputes.columns.status')" :width="150">
          <template #cell="{ record }">
            <Tag :color="statusColor(record.status)">{{ record.statusLabel }}</Tag>
          </template>
        </TableColumn>
        <TableColumn :title="t('admin.disputes.columns.risk')" :width="120">
          <template #cell="{ record }">
            <Tag :color="riskColor(record.riskLevel)">{{ record.riskLabel }}</Tag>
          </template>
        </TableColumn>
        <TableColumn :title="t('admin.disputes.columns.order')" data-index="orderNumber" :width="180" />
        <TableColumn :title="t('admin.disputes.columns.provider')" data-index="provider" :width="120" />
        <TableColumn :title="t('admin.disputes.columns.amount')" data-index="amount" :width="150" />
        <TableColumn :title="t('admin.disputes.columns.liability')" :width="160">
          <template #cell="{ record }">
            <TypographyText :type="record.liability === record.amount ? 'danger' : 'warning'">
              {{ record.liability }}
            </TypographyText>
          </template>
        </TableColumn>
        <TableColumn :title="t('admin.disputes.columns.deadline')" :width="220">
          <template #cell="{ record }">
            <TypographyText :type="record.overdue ? 'danger' : 'secondary'">
              {{ formatDate(record.evidenceDueAt) }}
            </TypographyText>
          </template>
        </TableColumn>
        <TableColumn :title="t('admin.disputes.columns.assignee')" :width="160">
          <template #cell="{ record }">
            {{ record.assignee || t('admin.disputes.unassigned') }}
          </template>
        </TableColumn>
        <TableColumn :title="t('admin.disputes.columns.rights')" :width="140">
          <template #cell="{ record }">
            <Tag :color="rightsColor(record.rightsStatus)">
              {{ t(`admin.disputes.rightsStatuses.${record.rightsStatus}`) }}
            </Tag>
          </template>
        </TableColumn>
      </Table>

      <div v-if="pagination.pages > 1" class="mt-5 flex justify-end">
        <Pagination
          :current="pagination.page"
          :total="pagination.count"
          :page-size="pagination.limit"
          show-total
          @change="applyFilters"
        />
      </div>
    </Card>
  </Space>

  <Drawer
    v-model:visible="drawerVisible"
    :width="'min(760px, 96vw)'"
    :title="t('admin.disputes.detailTitle')"
    :footer="false"
    unmount-on-close
  >
    <Spin :loading="drawerLoading" class="w-full">
      <Alert v-if="detailError" type="error" show-icon>{{ detailError }}</Alert>
      <template v-else-if="detail">
        <Space direction="vertical" size="large" fill>
          <Alert
            v-if="detail.dispute.overdue"
            type="error"
            show-icon
            :title="t('admin.disputes.evidenceOverdue')"
          >
            {{ t('admin.disputes.evidenceOverdueDescription') }}
          </Alert>
          <Alert
            v-else-if="detail.dispute.evidenceDueAt"
            type="warning"
            show-icon
            :title="t('admin.disputes.evidenceDeadline')"
          >
            <Progress
              :percent="dueProgress"
              :status="dueProgress >= 0.9 ? 'danger' : 'warning'"
              show-text
              class="mt-3"
            />
          </Alert>

          <Card class="risk-detail-card" :title="t('admin.disputes.caseSummary')" :bordered="false">
            <Descriptions :column="1" bordered size="small">
              <DescriptionsItem :label="t('admin.disputes.columns.status')">
                <Tag :color="statusColor(detail.dispute.status)">
                  {{ detail.dispute.statusLabel }}
                </Tag>
              </DescriptionsItem>
              <DescriptionsItem :label="t('admin.disputes.columns.order')">
                <Link :href="detail.dispute.orderUrl" class="arco-link">
                  {{ detail.dispute.orderNumber }}
                </Link>
              </DescriptionsItem>
              <DescriptionsItem :label="t('admin.disputes.columns.amount')">
                {{ detail.dispute.amount }}
              </DescriptionsItem>
              <DescriptionsItem :label="t('admin.disputes.columns.liability')">
                {{ detail.dispute.liability }}
              </DescriptionsItem>
              <DescriptionsItem :label="t('admin.disputes.offsetAmount')">
                {{ detail.dispute.offset }}
              </DescriptionsItem>
              <DescriptionsItem :label="t('admin.disputes.providerStatus')">
                {{ detail.dispute.providerStatus }}
              </DescriptionsItem>
              <DescriptionsItem :label="t('admin.disputes.reason')">
                {{ detail.dispute.reason }}
              </DescriptionsItem>
              <DescriptionsItem :label="t('admin.disputes.columns.rights')">
                <Tag :color="rightsColor(detail.dispute.rightsStatus)">
                  {{ detail.dispute.rightsStatusLabel }}
                </Tag>
              </DescriptionsItem>
              <DescriptionsItem :label="t('admin.disputes.retention')">
                {{ formatDate(detail.dispute.retentionUntil) }}
              </DescriptionsItem>
            </Descriptions>
          </Card>

          <Alert
            v-if="!detail.permissions.sensitiveRead"
            type="info"
            show-icon
            :title="t('admin.disputes.sensitiveHidden')"
          >
            {{ t('admin.disputes.sensitiveHiddenDescription') }}
          </Alert>
          <Card
            v-else-if="detail.dispute.sensitive"
            class="risk-detail-card"
            :title="t('admin.disputes.sensitiveDetails')"
            :bordered="false"
          >
            <Descriptions :column="1" bordered size="small">
              <DescriptionsItem :label="t('admin.disputes.providerDisputeId')">
                <code class="break-all">{{ detail.dispute.sensitive.providerDisputeId }}</code>
              </DescriptionsItem>
              <DescriptionsItem :label="t('admin.disputes.paymentReference')">
                <code class="break-all">
                  {{ detail.dispute.sensitive.paymentReference || t('common.notAvailable') }}
                </code>
              </DescriptionsItem>
              <DescriptionsItem :label="t('admin.disputes.paymentAmount')">
                {{ detail.dispute.sensitive.paymentAmount }}
              </DescriptionsItem>
            </Descriptions>
          </Card>

          <Card class="risk-detail-card" :title="t('admin.disputes.actionsTitle')" :bordered="false">
            <div class="flex flex-wrap gap-2">
              <Button v-if="detail.permissions.assign && detail.dispute.status !== 'closed'" @click="openAction('assign')">
                {{ t('admin.disputes.actions.assign') }}
              </Button>
              <Button v-if="detail.permissions.note" @click="openAction('note')">
                {{ t('admin.disputes.actions.note') }}
              </Button>
              <Button
                v-if="detail.permissions.evidenceSubmit && ['open', 'evidence_required', 'evidence_submitted', 'under_review'].includes(detail.dispute.status)"
                type="primary"
                @click="openAction('submit_evidence')"
              >
                {{ t('admin.disputes.actions.submit_evidence') }}
              </Button>
              <Button
                v-if="detail.permissions.acceptLoss && ['open', 'evidence_required', 'evidence_submitted', 'under_review'].includes(detail.dispute.status)"
                status="danger"
                @click="openHighRisk('accept_loss')"
              >
                {{ t('admin.disputes.actions.accept_loss') }}
              </Button>
              <Button
                v-if="detail.permissions.rightsManage && detail.dispute.rightsStatus !== 'frozen'"
                status="warning"
                @click="openHighRisk('freeze_rights')"
              >
                {{ t('admin.disputes.actions.freeze_rights') }}
              </Button>
              <Button
                v-if="detail.permissions.rightsManage && detail.dispute.rightsStatus !== 'revoked'"
                status="danger"
                @click="openHighRisk('revoke_rights')"
              >
                {{ t('admin.disputes.actions.revoke_rights') }}
              </Button>
              <Button
                v-if="detail.permissions.rightsManage && ['frozen', 'revoked'].includes(detail.dispute.rightsStatus)"
                @click="openHighRisk('restore_rights')"
              >
                {{ t('admin.disputes.actions.restore_rights') }}
              </Button>
              <Button
                v-if="detail.permissions.close && ['won', 'lost', 'withdrawn'].includes(detail.dispute.status)"
                @click="openAction('close')"
              >
                {{ t('admin.disputes.actions.close') }}
              </Button>
            </div>
          </Card>

          <Card class="risk-detail-card" :title="t('admin.disputes.evidenceTitle')" :bordered="false">
            <Empty v-if="detail.evidence.length === 0" :description="t('admin.disputes.evidenceEmpty')" />
            <div v-else class="grid gap-3">
              <div
                v-for="item in detail.evidence"
                :key="item.publicId"
                class="evidence-row"
              >
                <div class="min-w-0">
                  <div class="flex flex-wrap items-center gap-2">
                    <strong class="break-words">{{ item.title }}</strong>
                    <Tag :color="item.status === 'submitted' ? 'green' : 'gray'">
                      {{ item.statusLabel }}
                    </Tag>
                  </div>
                  <TypographyText type="secondary">
                    {{ item.filename }} · {{ formatBytes(item.byteSize) }} ·
                    {{ formatDate(item.submittedAt) }}
                  </TypographyText>
                  <code v-if="item.sha256" class="mt-1 block break-all text-xs">
                    {{ item.sha256 }}
                  </code>
                </div>
                <Button
                  v-if="item.downloadTokenUrl"
                  size="small"
                  :loading="downloadingId === item.publicId"
                  @click="downloadEvidence(item)"
                >
                  {{ t('common.download') }}
                </Button>
              </div>
            </div>
          </Card>

          <Card class="risk-detail-card" :title="t('admin.disputes.timelineTitle')" :bordered="false">
            <Timeline>
              <TimelineItem
                v-for="event in detail.events"
                :key="event.id"
                :dot-color="event.stale ? 'gray' : statusColor(event.toStatus || '')"
              >
                <div class="grid gap-1">
                  <div class="flex flex-wrap items-center gap-2">
                    <strong>{{ event.typeLabel }}</strong>
                    <Tag size="small">{{ event.sourceLabel }}</Tag>
                    <Tag v-if="event.stale" size="small" color="gray">
                      {{ t('admin.disputes.staleEvent') }}
                    </Tag>
                  </div>
                  <TypographyText type="secondary">
                    {{ event.actor || t('admin.disputes.systemActor') }} ·
                    {{ formatDate(event.createdAt) }}
                  </TypographyText>
                  <p v-if="event.note" class="m-0 whitespace-pre-wrap break-words">
                    {{ event.note }}
                  </p>
                </div>
              </TimelineItem>
            </Timeline>
          </Card>
        </Space>
      </template>
    </Spin>
  </Drawer>

  <Modal
    v-model:visible="actionVisible"
    :title="t(`admin.disputes.actions.${simpleAction}`)"
    :ok-text="t('common.confirm')"
    :cancel-text="t('common.cancel')"
    :ok-loading="actionSubmitting"
    :ok-button-props="{ disabled: !actionReason.trim() }"
    @ok="submitSimpleAction"
  >
    <Form layout="vertical">
      <FormItem
        v-if="simpleAction === 'assign'"
        :label="t('admin.disputes.assignee')"
        required
      >
        <Select v-model="assigneeId" :placeholder="t('admin.disputes.selectAssignee')">
          <Option v-for="option in assignees" :key="option.value" :value="option.value">
            {{ option.label }}
          </Option>
        </Select>
      </FormItem>
      <FormItem v-if="simpleAction === 'note'" :label="t('admin.disputes.note')" required>
        <Textarea v-model="actionNote" :max-length="5000" show-word-limit />
      </FormItem>
      <template v-if="simpleAction === 'submit_evidence'">
        <FormItem :label="t('admin.disputes.evidenceName')" required>
          <Input v-model="evidenceTitle" :max-length="120" />
        </FormItem>
        <FormItem :label="t('admin.disputes.evidenceFilename')" required>
          <Input v-model="evidenceFilename" :max-length="120" />
        </FormItem>
        <FormItem :label="t('admin.disputes.evidenceContent')" required>
          <Textarea
            v-model="evidenceContent"
            :auto-size="{ minRows: 6, maxRows: 14 }"
            :max-length="65536"
            show-word-limit
          />
        </FormItem>
      </template>
      <FormItem :label="t('admin.disputes.actionReason')" required>
        <Textarea
          v-model="actionReason"
          :auto-size="{ minRows: 3, maxRows: 6 }"
          :max-length="1000"
          show-word-limit
        />
      </FormItem>
    </Form>
  </Modal>

  <HighRiskActionModal
    v-if="detail"
    v-model:visible="highRiskVisible"
    :title="highRiskTitle"
    :authorization-url="detail.paths.authorizeAction"
    :action-url="detail.paths.executeAction"
    :payload="actionPayload()"
    @completed="highRiskCompleted"
  />
</template>

<style scoped>
.risk-summary-card {
  min-height: 112px;
  border-radius: var(--mcweb-radius-card, 12px);
  background: var(--color-bg-2);
}

.risk-workbench {
  border-radius: var(--mcweb-radius-section, 8px);
}

.risk-table :deep(.arco-table-container) {
  border-radius: var(--mcweb-radius-structure, 4px);
}

.risk-detail-card {
  border-radius: var(--mcweb-radius-card, 10px);
  background: var(--color-fill-1);
}

.evidence-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding: 12px 16px;
  border: 1px solid var(--color-border-2);
  border-radius: var(--mcweb-radius-control, 8px);
  background: var(--color-bg-2);
}

@media (max-width: 640px) {
  .evidence-row {
    align-items: stretch;
    flex-direction: column;
  }
}
</style>
