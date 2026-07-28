<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import {
  Alert,
  Button,
  Card,
  Descriptions,
  DescriptionsItem,
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
  Select,
  Statistic,
  Table,
  TableColumn,
  Tag,
  Textarea as ArcoTextarea,
  TypographyText,
} from '@mcweb/ui'
import ArcoAdminLayout from '@/layouts/ArcoAdminLayout.vue'
import { adminRoutes } from '@/lib/adminRoutes'
import { confirm } from '@/lib/arcoConfirm'
import { HttpError, postJson } from '@/lib/http'

defineOptions({ layout: ArcoAdminLayout })

type UploadRow = {
  id: number
  public_id: string
  filename: string
  size: string
  content_type: string | null
  downloads: number
  uploader: string | null
  kind: 'inline_image' | 'post_attachment'
  status:
    | 'reserved'
    | 'stored'
    | 'linked'
    | 'cleanup_pending'
    | 'cleanup_failed'
    | 'cleaned'
  scan_status: 'pending' | 'clean' | 'infected' | 'error'
  scan_result_code: string | null
  scanner: string | null
  scan_attempts: number
  cleanup_attempts: number
  quarantined: boolean
  linked: boolean
  post_url: string | null
  created_at: string | null
  scanned_at: string | null
  cleaned_at: string | null
  expires_at: string | null
  delete_url: string | null
  actions: {
    retry_scan_url?: string
    retry_cleanup_url?: string
    release_quarantine_url?: string
    release_confirmation?: string
  }
}

type PaginationMeta = {
  page: number
  pages: number
  count: number
  from: number | null
  to: number | null
}

type QuotaMetric = {
  used: number
  limit: number
}

type FilterName =
  | ''
  | 'scan_pending'
  | 'quarantined'
  | 'cleanup_failed'
  | 'cleaned'
  | 'orphans'

const filterValues: FilterName[] = [
  '',
  'scan_pending',
  'quarantined',
  'cleanup_failed',
  'cleaned',
  'orphans',
]

const props = defineProps<{
  uploads: UploadRow[]
  pagination: PaginationMeta
  filter: FilterName
  filterCounts: {
    all: number
    scan_pending: number
    quarantined: number
    cleanup_failed: number
    cleaned: number
    orphans: number
  }
  summary: {
    active: number
    scan_pending: number
    quarantined: number
    cleanup_failed: number
    cleaned: number
  }
  quotaUsage: {
    bytes: {
      usedLabel: string
      limitLabel: string | null
    }
    count: QuotaMetric
    hourlyCount: QuotaMetric
  }
  canManageSecurity: boolean
  orphanCount: number
  pruneUrl: string
}>()

const { locale, t, te } = useI18n()
const selectedFilter = ref<FilterName>(props.filter)
const releaseModalVisible = ref(false)
const releaseUpload = ref<UploadRow | null>(null)
const releaseReason = ref('')
const releaseConfirmation = ref('')
const releaseSubmitting = ref(false)
const releaseError = ref('')
const releaseReady = computed(() =>
  releaseReason.value.trim().length >= 12 &&
  releaseConfirmation.value === releaseUpload.value?.actions.release_confirmation,
)

watch(
  () => props.filter,
  (value) => {
    selectedFilter.value = value
  },
)

function translation(path: string, fallback: string) {
  return te(path) ? t(path) : fallback
}

function formatCount(value: number) {
  return new Intl.NumberFormat(locale.value).format(value)
}

function formatTime(value: string | null) {
  if (!value) return '—'
  return new Intl.DateTimeFormat(locale.value, {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(value))
}

function filterCount(value: FilterName) {
  return value ? props.filterCounts[value] : props.filterCounts.all
}

function filterLabel(value: FilterName) {
  return t(`admin.attachments.filters.${value || 'all'}`)
}

function kindLabel(value: string) {
  return translation(`admin.attachments.kinds.${value}`, value)
}

function lifecycleLabel(value: string) {
  return translation(`admin.attachments.statuses.${value}`, value)
}

function scanLabel(value: string) {
  return translation(`admin.attachments.scanStatuses.${value}`, value)
}

function scanResultLabel(value: string | null | undefined) {
  if (!value) return '—'
  return translation(
    `admin.attachments.scanResultCodes.${value}`,
    t('admin.attachments.scanResultUnknown'),
  )
}

function lifecycleColor(value: UploadRow['status']) {
  if (value === 'linked' || value === 'cleaned') return 'green'
  if (value === 'cleanup_failed') return 'red'
  if (value === 'cleanup_pending') return 'orange'
  if (value === 'stored') return 'arcoblue'
  return 'gray'
}

function scanColor(value: UploadRow['scan_status']) {
  if (value === 'clean') return 'green'
  if (value === 'infected') return 'red'
  if (value === 'error') return 'orange'
  return 'arcoblue'
}

function quotaCountLabel(metric: QuotaMetric) {
  const used = formatCount(metric.used)
  if (metric.limit === 0) {
    return t('admin.attachments.quotaUnlimitedValue', { used })
  }

  return t('admin.attachments.quotaUsedOfLimit', {
    used,
    limit: formatCount(metric.limit),
  })
}

function quotaBytesLabel() {
  if (!props.quotaUsage.bytes.limitLabel) {
    return t('admin.attachments.quotaUnlimitedValue', {
      used: props.quotaUsage.bytes.usedLabel,
    })
  }

  return t('admin.attachments.quotaUsedOfLimit', {
    used: props.quotaUsage.bytes.usedLabel,
    limit: props.quotaUsage.bytes.limitLabel,
  })
}

function setFilter(value: unknown) {
  const normalized = filterValues.includes(value as FilterName) ? (value as FilterName) : ''
  selectedFilter.value = normalized
  router.get(
    adminRoutes.forumAttachments,
    normalized ? { filter: normalized } : {},
    { preserveState: true, preserveScroll: true, replace: true },
  )
}

function visitPage(page: number) {
  router.get(
    adminRoutes.forumAttachments,
    { ...(props.filter ? { filter: props.filter } : {}), page },
    { preserveState: true, preserveScroll: true, replace: true },
  )
}

async function removeAttachment(upload: UploadRow) {
  if (!upload.delete_url) return

  const ok = await confirm({
    title: t('admin.attachments.deleteTitle'),
    message: t('admin.attachments.deleteConfirm', { name: upload.filename }),
    confirmLabel: t('admin.ui.delete'),
    variant: 'destructive',
  })
  if (!ok) return

  router.delete(upload.delete_url, { preserveScroll: true })
}

async function retryScan(upload: UploadRow) {
  if (!upload.actions.retry_scan_url) return

  const ok = await confirm({
    title: t('admin.attachments.retryScanTitle'),
    message: t('admin.attachments.retryScanConfirm', { name: upload.filename }),
    confirmLabel: t('admin.attachments.retryScan'),
  })
  if (!ok) return

  router.post(upload.actions.retry_scan_url, {}, { preserveScroll: true })
}

async function retryCleanup(upload: UploadRow) {
  if (!upload.actions.retry_cleanup_url) return

  const ok = await confirm({
    title: t('admin.attachments.retryCleanupTitle'),
    message: t('admin.attachments.retryCleanupConfirm', { name: upload.filename }),
    confirmLabel: t('admin.attachments.retryCleanup'),
  })
  if (!ok) return

  router.post(upload.actions.retry_cleanup_url, {}, { preserveScroll: true })
}

function openReleaseReview(upload: UploadRow) {
  if (!upload.actions.release_quarantine_url) return

  releaseUpload.value = upload
  releaseReason.value = ''
  releaseConfirmation.value = ''
  releaseError.value = ''
  releaseModalVisible.value = true
}

function closeReleaseReview() {
  if (releaseSubmitting.value) return
  releaseModalVisible.value = false
  releaseUpload.value = null
  releaseError.value = ''
}

function releaseErrorMessage(error: unknown) {
  if (error instanceof HttpError && error.body && typeof error.body === 'object') {
    const message = (error.body as { error?: unknown }).error
    if (typeof message === 'string' && message.length > 0) return message
  }

  return t('admin.attachments.releaseRequestFailed')
}

async function submitReleaseReview() {
  const upload = releaseUpload.value
  if (!upload?.actions.release_quarantine_url || !releaseReady.value) return

  releaseSubmitting.value = true
  releaseError.value = ''
  try {
    await postJson<{ released: true }>(upload.actions.release_quarantine_url, {
      reason: releaseReason.value.trim(),
      confirmation: releaseConfirmation.value,
    })
    releaseModalVisible.value = false
    releaseUpload.value = null
    releaseReason.value = ''
    releaseConfirmation.value = ''
    Message.success(t('admin.attachments.releaseSuccess'))
    router.reload({
      only: ['uploads', 'pagination', 'filterCounts', 'summary', 'quotaUsage'],
      preserveScroll: true,
    })
  } catch (error) {
    releaseError.value = releaseErrorMessage(error)
  } finally {
    releaseSubmitting.value = false
  }
}

async function prune() {
  const ok = await confirm({
    title: t('admin.attachments.pruneTitle'),
    message: t('admin.attachments.pruneConfirm', { count: props.orphanCount }),
    confirmLabel: t('admin.ui.delete'),
    variant: 'destructive',
  })
  if (!ok) return

  router.delete(props.pruneUrl)
}
</script>

<template>
  <section>
    <PageHeader
      :title="t('admin.attachments.title')"
      :subtitle="t('admin.attachments.subtitle')"
      :show-back="false"
      class="mb-5 !px-0"
    >
      <template v-if="canManageSecurity && orphanCount > 0" #extra>
        <Button type="outline" status="danger" @click="prune">
          {{ t('admin.attachments.prune', { count: orphanCount }) }}
        </Button>
      </template>
    </PageHeader>

    <Alert
      type="warning"
      show-icon
      :closable="false"
      :title="t('admin.attachments.securityNotice')"
      class="mb-5"
    />

    <Grid :cols="{ xs: 1, sm: 2, xl: 5 }" :col-gap="16" :row-gap="16" class="mb-5">
      <GridItem>
        <Card :bordered="false" class="bg-[var(--color-fill-1)]">
          <Statistic :title="t('admin.attachments.active')" :value="summary.active" />
        </Card>
      </GridItem>
      <GridItem>
        <Card :bordered="false" class="bg-[var(--color-fill-1)]">
          <Statistic :title="t('admin.attachments.scanPending')" :value="summary.scan_pending" />
        </Card>
      </GridItem>
      <GridItem>
        <Card :bordered="false" class="bg-[var(--color-fill-1)]">
          <Statistic :title="t('admin.attachments.quarantined')" :value="summary.quarantined" />
        </Card>
      </GridItem>
      <GridItem>
        <Card :bordered="false" class="bg-[var(--color-fill-1)]">
          <Statistic
            :title="t('admin.attachments.cleanupFailed')"
            :value="summary.cleanup_failed"
          />
        </Card>
      </GridItem>
      <GridItem>
        <Card :bordered="false" class="bg-[var(--color-fill-1)]">
          <Statistic :title="t('admin.attachments.cleaned')" :value="summary.cleaned" />
        </Card>
      </GridItem>
    </Grid>

    <Card :bordered="false" class="mb-5">
      <div class="mb-4">
        <h2 class="text-lg font-semibold">{{ t('admin.attachments.quotaTitle') }}</h2>
        <TypographyText type="secondary">
          {{ t('admin.attachments.quotaHint') }}
        </TypographyText>
      </div>

      <Descriptions
        :column="{ xs: 1, sm: 3 }"
        layout="vertical"
        :bordered="false"
      >
        <DescriptionsItem :label="t('admin.attachments.retainedBytes')">
          <span class="font-medium">{{ quotaBytesLabel() }}</span>
        </DescriptionsItem>
        <DescriptionsItem :label="t('admin.attachments.activeUploads')">
          <span class="font-medium">{{ quotaCountLabel(quotaUsage.count) }}</span>
        </DescriptionsItem>
        <DescriptionsItem :label="t('admin.attachments.hourlyAccepted')">
          <span class="font-medium">{{ quotaCountLabel(quotaUsage.hourlyCount) }}</span>
        </DescriptionsItem>
      </Descriptions>
    </Card>

    <Card :bordered="false">
      <div class="mb-5 flex flex-col gap-3 md:flex-row md:items-end md:justify-between">
        <div class="min-w-0">
          <h2 class="text-lg font-semibold">{{ t('admin.attachments.lifecycleTitle') }}</h2>
          <TypographyText type="secondary">
            {{ t('admin.attachments.lifecycleHint') }}
          </TypographyText>
        </div>

        <Select
          v-model="selectedFilter"
          class="w-full md:w-72"
          :aria-label="t('admin.attachments.filterLabel')"
          @change="setFilter"
        >
          <Option v-for="value in filterValues" :key="value || 'all'" :value="value">
            {{ filterLabel(value) }} ({{ formatCount(filterCount(value)) }})
          </Option>
        </Select>
      </div>

      <TypographyText type="secondary" class="mb-3 hidden lg:block">
        {{ t('admin.attachments.scrollHint') }}
      </TypographyText>

      <div class="hidden overflow-x-auto lg:block">
        <Table
          :data="uploads"
          :pagination="false"
          :bordered="false"
          :scroll="{ minWidth: 1340 }"
          row-key="id"
          stripe
        >
          <template #columns>
            <TableColumn :title="t('admin.attachments.colFile')" :width="300">
              <template #cell="{ record }">
                <div class="min-w-0 space-y-1.5">
                  <p class="truncate font-medium" :title="record.filename">
                    {{ record.filename }}
                  </p>
                  <p class="truncate font-mono text-xs text-[var(--color-text-3)]">
                    {{ record.public_id }}
                  </p>
                  <div class="flex flex-wrap gap-1.5">
                    <Tag color="arcoblue">{{ kindLabel(record.kind) }}</Tag>
                    <Tag v-if="record.content_type" color="gray">{{ record.content_type }}</Tag>
                  </div>
                </div>
              </template>
            </TableColumn>

            <TableColumn :title="t('admin.attachments.colScan')" :width="240">
              <template #cell="{ record }">
                <div class="space-y-1.5">
                  <div class="flex flex-wrap gap-1.5">
                    <Tag :color="scanColor(record.scan_status)">
                      {{ scanLabel(record.scan_status) }}
                    </Tag>
                    <Tag v-if="record.quarantined" color="red">
                      {{ t('admin.attachments.quarantined') }}
                    </Tag>
                  </div>
                  <p v-if="record.scan_result_code" class="text-xs text-[var(--color-text-2)]">
                    {{ scanResultLabel(record.scan_result_code) }}
                  </p>
                  <p class="text-xs text-[var(--color-text-3)]">
                    {{ record.scanner || '—' }}
                  </p>
                </div>
              </template>
            </TableColumn>

            <TableColumn :title="t('admin.attachments.colLifecycle')" :width="220">
              <template #cell="{ record }">
                <div class="space-y-1.5">
                  <Tag :color="lifecycleColor(record.status)">
                    {{ lifecycleLabel(record.status) }}
                  </Tag>
                  <p class="text-xs text-[var(--color-text-3)]">
                    {{
                      t('admin.attachments.attempts', {
                        scans: record.scan_attempts,
                        cleanups: record.cleanup_attempts,
                      })
                    }}
                  </p>
                  <p v-if="record.expires_at" class="text-xs text-[var(--color-text-3)]">
                    {{ t('admin.attachments.expiresAt', { time: formatTime(record.expires_at) }) }}
                  </p>
                </div>
              </template>
            </TableColumn>

            <TableColumn :title="t('admin.attachments.colOwner')" :width="180">
              <template #cell="{ record }">
                <div class="space-y-1.5">
                  <p>{{ record.uploader ? `@${record.uploader}` : '—' }}</p>
                  <a
                    v-if="record.linked && record.post_url"
                    :href="record.post_url"
                    target="_blank"
                    rel="noopener"
                    data-admin-hard-navigation
                    class="arco-link inline-block no-underline hover:underline"
                  >
                    {{ t('admin.attachments.linked') }}
                  </a>
                  <Tag v-else color="orange">{{ t('admin.attachments.orphan') }}</Tag>
                </div>
              </template>
            </TableColumn>

            <TableColumn :title="t('admin.attachments.colUsage')" :width="150">
              <template #cell="{ record }">
                <div class="space-y-1">
                  <p class="font-medium">{{ record.size }}</p>
                  <p class="text-xs text-[var(--color-text-3)]">
                    {{ t('admin.attachments.downloads', { count: record.downloads }) }}
                  </p>
                </div>
              </template>
            </TableColumn>

            <TableColumn :title="t('admin.attachments.colTime')" :width="190">
              <template #cell="{ record }">
                <div class="space-y-1 text-xs">
                  <p>{{ formatTime(record.created_at) }}</p>
                  <p v-if="record.scanned_at" class="text-[var(--color-text-3)]">
                    {{ t('admin.attachments.scannedAt', { time: formatTime(record.scanned_at) }) }}
                  </p>
                  <p v-if="record.cleaned_at" class="text-[var(--color-text-3)]">
                    {{ t('admin.attachments.cleanedAt', { time: formatTime(record.cleaned_at) }) }}
                  </p>
                </div>
              </template>
            </TableColumn>

            <TableColumn :title="t('admin.attachments.colActions')" :width="230" fixed="right">
              <template #cell="{ record }">
                <div class="flex flex-wrap gap-1">
                  <Button
                    v-if="record.actions.retry_scan_url"
                    type="outline"
                    status="warning"
                    size="small"
                    @click="retryScan(record)"
                  >
                    {{ t('admin.attachments.retryScan') }}
                  </Button>
                  <Button
                    v-if="record.actions.retry_cleanup_url"
                    type="outline"
                    status="warning"
                    size="small"
                    @click="retryCleanup(record)"
                  >
                    {{ t('admin.attachments.retryCleanup') }}
                  </Button>
                  <Button
                    v-if="record.actions.release_quarantine_url"
                    type="primary"
                    status="warning"
                    size="small"
                    @click="openReleaseReview(record)"
                  >
                    {{ t('admin.attachments.release') }}
                  </Button>
                  <Button
                    v-if="record.delete_url"
                    type="text"
                    status="danger"
                    size="small"
                    @click="removeAttachment(record)"
                  >
                    {{ t('admin.ui.delete') }}
                  </Button>
                </div>
              </template>
            </TableColumn>
          </template>
          <template #empty>
            <Empty :description="t('admin.attachments.empty')" />
          </template>
        </Table>
      </div>

      <div class="space-y-3 lg:hidden">
        <Card
          v-for="upload in uploads"
          :key="upload.id"
          :bordered="false"
          class="bg-[var(--color-fill-1)]"
        >
          <div class="space-y-4">
            <div class="flex items-start justify-between gap-3">
              <div class="min-w-0 flex-1">
                <p class="break-words font-semibold">{{ upload.filename }}</p>
                <p class="mt-1 break-all font-mono text-xs text-[var(--color-text-3)]">
                  {{ upload.public_id }}
                </p>
              </div>
              <Tag :color="scanColor(upload.scan_status)">
                {{ scanLabel(upload.scan_status) }}
              </Tag>
            </div>

            <div class="flex flex-wrap gap-1.5">
              <Tag color="arcoblue">{{ kindLabel(upload.kind) }}</Tag>
              <Tag :color="lifecycleColor(upload.status)">
                {{ lifecycleLabel(upload.status) }}
              </Tag>
              <Tag v-if="upload.quarantined" color="red">
                {{ t('admin.attachments.quarantined') }}
              </Tag>
              <Tag v-if="!upload.linked" color="orange">{{ t('admin.attachments.orphan') }}</Tag>
            </div>

            <div class="grid gap-3 text-sm sm:grid-cols-2">
              <div>
                <p class="text-xs text-[var(--color-text-3)]">
                  {{ t('admin.attachments.colOwner') }}
                </p>
                <p class="mt-1">{{ upload.uploader ? `@${upload.uploader}` : '—' }}</p>
              </div>
              <div>
                <p class="text-xs text-[var(--color-text-3)]">
                  {{ t('admin.attachments.colUsage') }}
                </p>
                <p class="mt-1">{{ upload.size }}</p>
              </div>
              <div>
                <p class="text-xs text-[var(--color-text-3)]">
                  {{ t('admin.attachments.scanResult') }}
                </p>
                <p class="mt-1 text-xs">
                  {{ scanResultLabel(upload.scan_result_code) }}
                </p>
              </div>
              <div>
                <p class="text-xs text-[var(--color-text-3)]">
                  {{ t('admin.attachments.colTime') }}
                </p>
                <p class="mt-1">{{ formatTime(upload.created_at) }}</p>
              </div>
            </div>

            <div class="flex flex-wrap items-center justify-between gap-2">
              <a
                v-if="upload.linked && upload.post_url"
                :href="upload.post_url"
                target="_blank"
                rel="noopener"
                data-admin-hard-navigation
                class="arco-link font-medium no-underline hover:underline"
              >
                {{ t('admin.attachments.openPost') }}
              </a>
              <span v-else />
              <div class="flex flex-wrap justify-end gap-1">
                <Button
                  v-if="upload.actions.retry_scan_url"
                  type="outline"
                  status="warning"
                  size="small"
                  @click="retryScan(upload)"
                >
                  {{ t('admin.attachments.retryScan') }}
                </Button>
                <Button
                  v-if="upload.actions.retry_cleanup_url"
                  type="outline"
                  status="warning"
                  size="small"
                  @click="retryCleanup(upload)"
                >
                  {{ t('admin.attachments.retryCleanup') }}
                </Button>
                <Button
                  v-if="upload.actions.release_quarantine_url"
                  type="primary"
                  status="warning"
                  size="small"
                  @click="openReleaseReview(upload)"
                >
                  {{ t('admin.attachments.release') }}
                </Button>
                <Button
                  v-if="upload.delete_url"
                  type="text"
                  status="danger"
                  size="small"
                  @click="removeAttachment(upload)"
                >
                  {{ t('admin.ui.delete') }}
                </Button>
              </div>
            </div>
          </div>
        </Card>

        <Empty v-if="uploads.length === 0" :description="t('admin.attachments.empty')" />
      </div>

      <div
        v-if="pagination.pages > 1"
        class="mt-5 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"
      >
        <TypographyText type="secondary">
          {{ pagination.from }}–{{ pagination.to }} / {{ pagination.count }}
        </TypographyText>
        <Pagination
          :current="pagination.page"
          :total="pagination.pages"
          :page-size="1"
          :show-page-size="false"
          @change="visitPage"
        />
      </div>
    </Card>

    <Modal
      v-model:visible="releaseModalVisible"
      :title="t('admin.attachments.releaseTitle')"
      :footer="false"
      :mask-closable="!releaseSubmitting"
      :esc-to-close="!releaseSubmitting"
      :width="'min(600px, calc(100vw - 32px))'"
      @cancel="closeReleaseReview"
    >
      <Alert
        v-if="releaseError"
        type="error"
        show-icon
        :closable="false"
        class="mb-4"
      >
        {{ releaseError }}
      </Alert>

      <Alert
        type="warning"
        show-icon
        :closable="false"
        :title="t('admin.attachments.releaseWarning')"
        class="mb-5"
      />

      <Descriptions :column="1" bordered size="small" class="mb-5">
        <DescriptionsItem :label="t('admin.attachments.colFile')">
          {{ releaseUpload?.filename }}
        </DescriptionsItem>
        <DescriptionsItem :label="t('admin.attachments.scanResult')">
          <TypographyText>{{ scanResultLabel(releaseUpload?.scan_result_code) }}</TypographyText>
        </DescriptionsItem>
      </Descriptions>

      <Form :model="{ reason: releaseReason, confirmation: releaseConfirmation }" layout="vertical">
        <FormItem field="reason" :label="t('admin.attachments.releaseReason')" required>
          <ArcoTextarea
            v-model="releaseReason"
            :placeholder="t('admin.attachments.releaseReasonPlaceholder')"
            :max-length="1000"
            show-word-limit
            :auto-size="{ minRows: 4, maxRows: 8 }"
            :disabled="releaseSubmitting"
          />
          <template #extra>{{ t('admin.attachments.releaseReasonHelp') }}</template>
        </FormItem>

        <FormItem field="confirmation" :label="t('admin.attachments.releaseConfirmation')" required>
          <Input
            v-model="releaseConfirmation"
            :placeholder="releaseUpload?.actions.release_confirmation"
            :disabled="releaseSubmitting"
            autocomplete="off"
          />
          <template #extra>
            {{ t('admin.attachments.releaseConfirmationHelp') }}
            <TypographyText code>
              {{ releaseUpload?.actions.release_confirmation }}
            </TypographyText>
          </template>
        </FormItem>

        <div class="flex flex-wrap justify-end gap-2">
          <Button :disabled="releaseSubmitting" @click="closeReleaseReview">
            {{ t('admin.ui.cancel') }}
          </Button>
          <Button
            type="primary"
            status="warning"
            :loading="releaseSubmitting"
            :disabled="!releaseReady"
            @click="submitReleaseReview"
          >
            {{ t('admin.attachments.releaseSubmit') }}
          </Button>
        </div>
      </Form>
    </Modal>
  </section>
</template>
