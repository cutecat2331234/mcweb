<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, reactive, ref, watch } from 'vue'
import { router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import {
  Alert,
  Button,
  Card,
  Checkbox,
  DatePicker,
  Descriptions,
  DescriptionsItem,
  Divider,
  Drawer,
  Empty,
  Form,
  FormItem,
  Grid,
  GridItem,
  Message,
  Option,
  PageHeader,
  Pagination,
  Select,
  Space,
  Spin,
  Table,
  TableColumn,
  Tag,
  Textarea,
  TypographyParagraph,
  TypographyText,
} from '@mcweb/ui'
import AdminLayout from '@/layouts/AdminLayout.vue'
import ModerationActionModal, {
  type ModerationExecutionResponse,
} from '@/components/admin/ModerationActionModal.vue'
import { getJson, HttpError, postJson } from '@/lib/http'

defineOptions({ layout: AdminLayout })

type PrimitiveOption = string | number
type FilterOption =
  | PrimitiveOption
  | {
      value: PrimitiveOption
      label?: string
      name?: string
      username?: string
      id?: PrimitiveOption
    }

type ModerationCase = {
  id: number
  source_kind: string
  status: string
  priority: string
  risk_level: string
  title: string
  summary: string
  section: string | { id?: number; name?: string } | null
  assignee: string | { id?: number; name?: string; username?: string } | null
  claimed_at: string | null
  updated_at: string
  lock_version: number
  available_actions: string[]
}

type Evidence = {
  kind?: string
  label?: string
  value?: unknown
  content?: unknown
  truncated?: boolean
  cropped?: boolean
  [key: string]: unknown
}

type EvidenceAttachment = {
  public_id: string
  filename: string
  byte_size: number
  download_url: string
}

type Note = {
  id?: number
  body: string
  author?: string | { name?: string; username?: string } | null
  created_at?: string | null
}

type ModerationCaseDetail = ModerationCase & {
  evidence: Evidence[] | Evidence | string | null
  notes: Note[]
  assignable_staff: FilterOption[]
}

type Filters = {
  source_kind: string | number
  status: string | number
  priority: string | number
  section_id: string | number
  assignee_id: string | number
  from: string
  to: string
  risk_level: string | number
}

const props = defineProps<{
  cases: ModerationCase[]
  pagination: {
    page: number
    pages: number
    count: number
  }
  filters: Partial<Filters>
  filter_options: {
    source_kinds: FilterOption[]
    statuses: FilterOption[]
    priorities: FilterOption[]
    risk_levels: FilterOption[]
    sections: FilterOption[]
    move_sections: FilterOption[]
    staff: FilterOption[]
  }
  capabilities: {
    can_assign: boolean
    can_note: boolean
  }
  sync_warning?: string | null
}>()

const { locale, t } = useI18n()
const rows = ref<ModerationCase[]>([...props.cases])
const filters = reactive<Filters>({
  source_kind: props.filters.source_kind || '',
  status: props.filters.status || '',
  priority: props.filters.priority || '',
  section_id: props.filters.section_id || '',
  assignee_id: props.filters.assignee_id || '',
  from: props.filters.from || '',
  to: props.filters.to || '',
  risk_level: props.filters.risk_level || '',
})
const selectedCaseIds = ref<number[]>([])
const bulkAction = ref('')
const bulkMoveSectionId = ref<string | number>('')
const bulkVisible = ref(false)
const refreshAfterBulkClose = ref(false)
const drawerVisible = ref(false)
const drawerLoading = ref(false)
const detail = ref<ModerationCaseDetail | null>(null)
const detailError = ref('')
const assigning = ref(false)
const assigneeId = ref<string | number | null | undefined>('')
const drawerMoveSectionId = ref<string | number>('')
const noteBody = ref('')
const noteSubmitting = ref(false)
const actionLoadingIds = ref<number[]>([])
const pageError = ref('')
const isMobile = ref(false)
let viewportQuery: MediaQueryList | null = null

function syncViewport(event?: MediaQueryListEvent) {
  isMobile.value = event?.matches ?? viewportQuery?.matches ?? false
}

onMounted(() => {
  viewportQuery = window.matchMedia('(max-width: 767px)')
  syncViewport()
  viewportQuery.addEventListener('change', syncViewport)
})

onBeforeUnmount(() => {
  viewportQuery?.removeEventListener('change', syncViewport)
})

const rowSelection = {
  type: 'checkbox' as const,
  showCheckedAll: true,
  onlyCurrent: true,
  width: 46,
}

watch(
  () => props.cases,
  (value) => {
    rows.value = [...value]
    const availableIds = new Set(value.map((item) => item.id))
    selectedCaseIds.value = selectedCaseIds.value.filter((id) => availableIds.has(id))
  },
)

watch(
  () => props.filters,
  (value) => {
    Object.assign(filters, {
      source_kind: value.source_kind || '',
      status: value.status || '',
      priority: value.priority || '',
      section_id: value.section_id || '',
      assignee_id: value.assignee_id || '',
      from: value.from || '',
      to: value.to || '',
      risk_level: value.risk_level || '',
    })
  },
)

watch(bulkVisible, (visible) => {
  if (visible || !refreshAfterBulkClose.value) return
  const affectedDetailId =
    detail.value && selectedCaseIds.value.includes(detail.value.id)
      ? detail.value.id
      : null
  refreshAfterBulkClose.value = false
  selectedCaseIds.value = []
  bulkAction.value = ''
  bulkMoveSectionId.value = ''
  router.reload({
    only: ['cases', 'pagination'],
    preserveScroll: true,
  })
  if (affectedDetailId && drawerVisible.value) void loadDetail(affectedDetailId)
})

const selectedCases = computed(() => {
  const ids = new Set(selectedCaseIds.value)
  return rows.value.filter((item) => ids.has(item.id))
})
const commonActions = computed(() => {
  if (!selectedCases.value.length) return []
  return selectedCases.value[0].available_actions
    .filter((action) => !['claim', 'assign', 'note'].includes(action))
    .filter((action) =>
      selectedCases.value.every((item) => item.available_actions.includes(action)),
    )
})
const bulkAttributes = computed<Record<string, unknown>>(() =>
  bulkAction.value === 'move_topic' && bulkMoveSectionId.value !== ''
    ? { section_id: bulkMoveSectionId.value }
    : {},
)
const canOpenBulk = computed(() =>
  selectedCaseIds.value.length > 0 &&
  commonActions.value.includes(bulkAction.value) &&
  (bulkAction.value !== 'move_topic' || bulkMoveSectionId.value !== ''),
)
const activeFilterCount = computed(() =>
  Object.values(filters).filter((value) => value !== '').length,
)
const pageSize = computed(() =>
  Math.max(1, Math.ceil(props.pagination.count / Math.max(props.pagination.pages, 1))),
)
const evidenceItems = computed<Evidence[]>(() => {
  if (!detail.value?.evidence) return []
  if (typeof detail.value.evidence === 'string') {
    return [{ kind: 'text', content: detail.value.evidence }]
  }
  return Array.isArray(detail.value.evidence)
    ? detail.value.evidence
    : [detail.value.evidence]
})
const evidenceWasTruncated = computed(() =>
  evidenceItems.value.some((item) => item.truncated === true || item.cropped === true),
)

function optionValue(option: FilterOption) {
  if (typeof option === 'string' || typeof option === 'number') return option
  return option.value ?? option.id ?? ''
}

function optionLabel(option: FilterOption, namespace?: string) {
  if (typeof option === 'object') {
    if (option.label) return option.label
    if (option.name) return option.name
    if (option.username) return option.username
  }
  const value = optionValue(option)
  return namespace
    ? t(`admin.moderationWorkbench.${namespace}.${value}`)
    : String(value)
}

function entityLabel(value: ModerationCase['section'] | ModerationCase['assignee']) {
  if (!value) return t('admin.moderationWorkbench.common.unassigned')
  if (typeof value === 'string') return value
  return value.name || value.username || t('admin.moderationWorkbench.common.notAvailable')
}

function formatTime(value: string | null | undefined) {
  if (!value) return t('admin.moderationWorkbench.common.notAvailable')
  return new Intl.DateTimeFormat(locale.value, {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(value))
}

function statusColor(status: string) {
  if (['resolved', 'released', 'completed', 'approved'].includes(status)) return 'green'
  if (['rejected', 'deleted', 'banned'].includes(status)) return 'red'
  if (['claimed', 'in_progress'].includes(status)) return 'arcoblue'
  return 'orange'
}

function riskColor(risk: string) {
  if (['critical', 'high'].includes(risk)) return 'red'
  if (risk === 'medium') return 'orange'
  return 'green'
}

function priorityColor(priority: string) {
  if (['urgent', 'critical'].includes(priority)) return 'red'
  if (priority === 'high') return 'orange'
  return 'blue'
}

function query(page = 1) {
  return Object.fromEntries(
    Object.entries({ ...filters, page }).filter(([, value]) => value !== ''),
  )
}

function applyFilters() {
  router.get('/admin/forum/moderation-workbench', query(), {
    preserveScroll: true,
    preserveState: true,
    replace: true,
  })
}

function clearFilters() {
  Object.assign(filters, {
    source_kind: '',
    status: '',
    priority: '',
    section_id: '',
    assignee_id: '',
    from: '',
    to: '',
    risk_level: '',
  })
  applyFilters()
}

function visitPage(page: number) {
  router.get('/admin/forum/moderation-workbench', query(page), {
    preserveScroll: true,
    preserveState: true,
    replace: true,
  })
}

function errorText(error: unknown) {
  if (error instanceof HttpError && error.body && typeof error.body === 'object') {
    const body = error.body as { error?: unknown; message?: unknown }
    if (typeof body.error === 'string' && body.error.length > 0) return body.error
    if (typeof body.message === 'string' && body.message.length > 0) return body.message
  }
  return t('admin.moderationWorkbench.requestFailed')
}

function replaceCase(updated: ModerationCase) {
  const index = rows.value.findIndex((item) => item.id === updated.id)
  if (index >= 0) rows.value.splice(index, 1, { ...rows.value[index], ...updated })
  if (detail.value?.id === updated.id) detail.value = { ...detail.value, ...updated }
}

async function loadDetail(id: number) {
  drawerLoading.value = true
  detailError.value = ''
  try {
    const response = await getJson<{ case: ModerationCaseDetail }>(
      `/admin/forum/moderation-workbench/${id}`,
    )
    detail.value = response.case
    assigneeId.value =
      typeof response.case.assignee === 'object' && response.case.assignee?.id
        ? response.case.assignee.id
        : ''
  } catch (error) {
    detailError.value = errorText(error)
  } finally {
    drawerLoading.value = false
  }
}

function openDetail(item: ModerationCase) {
  detail.value = null
  noteBody.value = ''
  assigneeId.value = ''
  drawerMoveSectionId.value = ''
  drawerVisible.value = true
  void loadDetail(item.id)
}

async function claim(item: ModerationCase) {
  if (!item.available_actions.includes('claim')) return
  actionLoadingIds.value.push(item.id)
  pageError.value = ''
  try {
    const response = await postJson<{ case?: ModerationCase }>(
      `/admin/forum/moderation-workbench/${item.id}/claim`,
      { lock_version: item.lock_version },
    )
    if (response.case) {
      replaceCase(response.case)
    } else {
      router.reload({ only: ['cases'], preserveScroll: true })
    }
    Message.success(t('admin.moderationWorkbench.claimed'))
  } catch (error) {
    pageError.value = errorText(error)
  } finally {
    actionLoadingIds.value = actionLoadingIds.value.filter((id) => id !== item.id)
  }
}

async function assign() {
  if (!detail.value || !props.capabilities.can_assign) return
  assigning.value = true
  detailError.value = ''
  try {
    const caseId = detail.value.id
    const response = await postJson<{ case?: ModerationCaseDetail }>(
      `/admin/forum/moderation-workbench/${detail.value.id}/assign`,
      {
        assignee_id:
          assigneeId.value === '' || assigneeId.value == null
            ? null
            : assigneeId.value,
        lock_version: detail.value.lock_version,
      },
    )
    if (response.case) {
      detail.value = response.case
      replaceCase(response.case)
    } else {
      await loadDetail(caseId)
      router.reload({ only: ['cases'], preserveScroll: true })
    }
    Message.success(t('admin.moderationWorkbench.assigned'))
  } catch (error) {
    detailError.value = errorText(error)
  } finally {
    assigning.value = false
  }
}

async function addNote() {
  if (!detail.value || !props.capabilities.can_note || noteBody.value.trim().length === 0) return
  noteSubmitting.value = true
  detailError.value = ''
  try {
    const caseId = detail.value.id
    const response = await postJson<{ case?: ModerationCaseDetail }>(
      `/admin/forum/moderation-workbench/${detail.value.id}/notes`,
      {
        body: noteBody.value.trim(),
        lock_version: detail.value.lock_version,
      },
    )
    if (response.case) {
      detail.value = response.case
      replaceCase(response.case)
    } else {
      await loadDetail(caseId)
      router.reload({ only: ['cases'], preserveScroll: true })
    }
    noteBody.value = ''
    Message.success(t('admin.moderationWorkbench.noteAdded'))
  } catch (error) {
    detailError.value = errorText(error)
  } finally {
    noteSubmitting.value = false
  }
}

function openAction(action: string, ids: number[]) {
  selectedCaseIds.value = ids
  bulkAction.value = action
  bulkMoveSectionId.value =
    action === 'move_topic' ? drawerMoveSectionId.value : ''
  if (action === 'move_topic' && bulkMoveSectionId.value === '') return
  bulkVisible.value = true
}

function handleBulkCompleted(_result: ModerationExecutionResponse) {
  refreshAfterBulkClose.value = true
}

function displayEvidence(item: Evidence) {
  const { attachments: _attachments, ...evidence } = item
  const value = item.content ?? item.value ?? evidence
  if (typeof value === 'string') return value
  return JSON.stringify(value, null, 2)
}

function evidenceAttachments(item: Evidence): EvidenceAttachment[] {
  if (!Array.isArray(item.attachments)) return []
  return item.attachments.filter((attachment): attachment is EvidenceAttachment =>
    Boolean(
      attachment &&
      typeof attachment === 'object' &&
      typeof (attachment as EvidenceAttachment).public_id === 'string' &&
      typeof (attachment as EvidenceAttachment).download_url === 'string',
    ),
  )
}

function evidenceLabel(item: Evidence, index: number) {
  if (item.label) return item.label
  if (item.kind) return t(`admin.moderationWorkbench.evidenceKinds.${item.kind}`)
  if (typeof item.type === 'string') {
    return t(`admin.moderationWorkbench.evidenceKinds.${item.type}`)
  }
  return t('admin.moderationWorkbench.evidenceItem', { index: index + 1 })
}

function noteAuthor(note: Note) {
  if (!note.author) return t('admin.moderationWorkbench.common.unknownActor')
  if (typeof note.author === 'string') return note.author
  return note.author.name || note.author.username ||
    t('admin.moderationWorkbench.common.unknownActor')
}
</script>

<template>
  <Space direction="vertical" :size="16" fill>
    <PageHeader
      :title="t('admin.moderationWorkbench.title')"
      :subtitle="t('admin.moderationWorkbench.subtitle')"
      :show-back="false"
    />

    <Alert
      v-if="pageError || sync_warning"
      :type="pageError ? 'error' : 'warning'"
      show-icon
      :closable="false"
    >
      {{ pageError || sync_warning }}
    </Alert>

    <Card :bordered="false">
      <Form :model="filters" layout="vertical" @submit="applyFilters">
        <Grid :cols="{ xs: 1, sm: 2, lg: 4 }" :col-gap="16" :row-gap="4">
          <GridItem>
            <FormItem field="source_kind" :label="t('admin.moderationWorkbench.filters.sourceKind')">
              <Select v-model="filters.source_kind" allow-clear allow-search>
                <Option
                  v-for="option in filter_options.source_kinds"
                  :key="optionValue(option)"
                  :value="optionValue(option)"
                >
                  {{ optionLabel(option, 'sourceKinds') }}
                </Option>
              </Select>
            </FormItem>
          </GridItem>
          <GridItem>
            <FormItem field="status" :label="t('admin.moderationWorkbench.filters.status')">
              <Select v-model="filters.status" allow-clear allow-search>
                <Option
                  v-for="option in filter_options.statuses"
                  :key="optionValue(option)"
                  :value="optionValue(option)"
                >
                  {{ optionLabel(option, 'statuses') }}
                </Option>
              </Select>
            </FormItem>
          </GridItem>
          <GridItem>
            <FormItem field="priority" :label="t('admin.moderationWorkbench.filters.priority')">
              <Select v-model="filters.priority" allow-clear allow-search>
                <Option
                  v-for="option in filter_options.priorities"
                  :key="optionValue(option)"
                  :value="optionValue(option)"
                >
                  {{ optionLabel(option, 'priorities') }}
                </Option>
              </Select>
            </FormItem>
          </GridItem>
          <GridItem>
            <FormItem field="risk_level" :label="t('admin.moderationWorkbench.filters.riskLevel')">
              <Select v-model="filters.risk_level" allow-clear allow-search>
                <Option
                  v-for="option in filter_options.risk_levels"
                  :key="optionValue(option)"
                  :value="optionValue(option)"
                >
                  {{ optionLabel(option, 'riskLevels') }}
                </Option>
              </Select>
            </FormItem>
          </GridItem>
          <GridItem>
            <FormItem field="section_id" :label="t('admin.moderationWorkbench.filters.section')">
              <Select v-model="filters.section_id" allow-clear allow-search>
                <Option
                  v-for="option in filter_options.sections"
                  :key="optionValue(option)"
                  :value="optionValue(option)"
                >
                  {{ optionLabel(option) }}
                </Option>
              </Select>
            </FormItem>
          </GridItem>
          <GridItem>
            <FormItem field="assignee_id" :label="t('admin.moderationWorkbench.filters.assignee')">
              <Select v-model="filters.assignee_id" allow-clear allow-search>
                <Option value="me">{{ t('admin.moderationWorkbench.columns.me') }}</Option>
                <Option value="unassigned">
                  {{ t('admin.moderationWorkbench.columns.unassigned') }}
                </Option>
                <Option
                  v-for="option in filter_options.staff"
                  :key="optionValue(option)"
                  :value="optionValue(option)"
                >
                  {{ optionLabel(option) }}
                </Option>
              </Select>
            </FormItem>
          </GridItem>
          <GridItem>
            <FormItem field="from" :label="t('admin.moderationWorkbench.filters.from')">
              <DatePicker
                v-model="filters.from"
                value-format="YYYY-MM-DD"
                format="YYYY-MM-DD"
                allow-clear
                long
              />
            </FormItem>
          </GridItem>
          <GridItem>
            <FormItem field="to" :label="t('admin.moderationWorkbench.filters.to')">
              <DatePicker
                v-model="filters.to"
                value-format="YYYY-MM-DD"
                format="YYYY-MM-DD"
                allow-clear
                long
              />
            </FormItem>
          </GridItem>
        </Grid>

        <Space wrap>
          <Button type="primary" shape="round" html-type="submit">
            {{ t('admin.moderationWorkbench.filters.apply') }}
          </Button>
          <Button shape="round" :disabled="activeFilterCount === 0" @click="clearFilters">
            {{ t('admin.moderationWorkbench.filters.clear') }}
          </Button>
        </Space>
      </Form>
    </Card>

    <Card :bordered="false">
      <Space direction="vertical" :size="16" fill>
        <Card
          v-if="selectedCaseIds.length"
          :title="t('admin.moderationWorkbench.bulk.review', { count: selectedCaseIds.length })"
          :bordered="true"
          size="small"
        >
          <Grid :cols="{ xs: 1, sm: 2, lg: 3 }" :col-gap="12" :row-gap="12">
            <GridItem>
              <Select
                v-model="bulkAction"
                :placeholder="t('admin.moderationWorkbench.bulk.selectAction')"
                allow-clear
              >
                <Option v-for="action in commonActions" :key="action" :value="action">
                  {{ t(`admin.moderationWorkbench.actions.${action}`) }}
                </Option>
              </Select>
            </GridItem>
            <GridItem>
              <Select
                v-if="bulkAction === 'move_topic'"
                v-model="bulkMoveSectionId"
                :placeholder="t('admin.moderationWorkbench.bulk.destinationSection')"
                allow-search
              >
                <Option
                  v-for="option in filter_options.move_sections"
                  :key="optionValue(option)"
                  :value="optionValue(option)"
                >
                  {{ optionLabel(option) }}
                </Option>
              </Select>
            </GridItem>
            <GridItem>
              <Button
                type="primary"
                status="warning"
                long
                :disabled="!canOpenBulk"
                @click="bulkVisible = true"
              >
                {{ t('admin.moderationWorkbench.bulk.review', { count: selectedCaseIds.length }) }}
              </Button>
            </GridItem>
          </Grid>
        </Card>

        <Empty
          v-if="rows.length === 0"
          :description="t('admin.moderationWorkbench.empty')"
        >
          <template #extra>
            <Button v-if="activeFilterCount" shape="round" @click="clearFilters">
              {{ t('admin.moderationWorkbench.filters.clear') }}
            </Button>
          </template>
        </Empty>

        <Table
          v-else-if="!isMobile"
          v-model:selected-keys="selectedCaseIds"
          :data="rows"
          :pagination="false"
          :row-selection="rowSelection"
          :bordered="{ wrapper: true }"
          :scroll="{ minWidth: 1260 }"
          row-key="id"
          stripe
        >
          <template #columns>
            <TableColumn :title="t('admin.moderationWorkbench.columns.case')" :width="300">
              <template #cell="{ record }">
                <Space direction="vertical" :size="2" fill>
                  <Button type="text" long @click="openDetail(record)">
                    {{ record.title }}
                  </Button>
                  <TypographyText type="secondary" :ellipsis="{ rows: 2 }">
                    {{ record.summary }}
                  </TypographyText>
                </Space>
              </template>
            </TableColumn>
            <TableColumn :title="t('admin.moderationWorkbench.columns.source')" :width="145">
              <template #cell="{ record }">
                {{ t(`admin.moderationWorkbench.sourceKinds.${record.source_kind}`) }}
              </template>
            </TableColumn>
            <TableColumn :title="t('admin.moderationWorkbench.columns.status')" :width="135">
              <template #cell="{ record }">
                <Tag :color="statusColor(record.status)">
                  {{ t(`admin.moderationWorkbench.statuses.${record.status}`) }}
                </Tag>
              </template>
            </TableColumn>
            <TableColumn :title="t('admin.moderationWorkbench.columns.priority')" :width="125">
              <template #cell="{ record }">
                <Tag :color="priorityColor(record.priority)">
                  {{ t(`admin.moderationWorkbench.priorities.${record.priority}`) }}
                </Tag>
              </template>
            </TableColumn>
            <TableColumn :title="t('admin.moderationWorkbench.columns.risk')" :width="120">
              <template #cell="{ record }">
                <Tag :color="riskColor(record.risk_level)">
                  {{ t(`admin.moderationWorkbench.riskLevels.${record.risk_level}`) }}
                </Tag>
              </template>
            </TableColumn>
            <TableColumn :title="t('admin.moderationWorkbench.columns.section')" :width="150">
              <template #cell="{ record }">{{ entityLabel(record.section) }}</template>
            </TableColumn>
            <TableColumn :title="t('admin.moderationWorkbench.columns.assignee')" :width="150">
              <template #cell="{ record }">{{ entityLabel(record.assignee) }}</template>
            </TableColumn>
            <TableColumn :title="t('admin.moderationWorkbench.columns.updatedAt')" :width="190">
              <template #cell="{ record }">{{ formatTime(record.updated_at) }}</template>
            </TableColumn>
            <TableColumn
              :title="t('admin.moderationWorkbench.columns.actions')"
              :width="210"
              fixed="right"
            >
              <template #cell="{ record }">
                <Space wrap>
                  <Button size="small" @click="openDetail(record)">
                    {{ t('admin.moderationWorkbench.details.open') }}
                  </Button>
                  <Button
                    v-if="record.available_actions.includes('claim')"
                    size="small"
                    type="primary"
                    :loading="actionLoadingIds.includes(record.id)"
                    @click="claim(record)"
                  >
                    {{ t('admin.moderationWorkbench.actions.claim') }}
                  </Button>
                </Space>
              </template>
            </TableColumn>
          </template>
        </Table>

        <Space v-else direction="vertical" :size="12" fill>
          <Card
            v-for="item in rows"
            :key="item.id"
            :bordered="true"
            hoverable
          >
            <template #title>
              <Button type="text" @click="openDetail(item)">{{ item.title }}</Button>
            </template>
            <template #extra>
              <Checkbox
                :model-value="selectedCaseIds.includes(item.id)"
                :aria-label="t('admin.moderationWorkbench.selectCase', { id: item.id })"
                @change="(checked) => {
                  selectedCaseIds = checked
                    ? Array.from(new Set([...selectedCaseIds, item.id]))
                    : selectedCaseIds.filter((id) => id !== item.id)
                }"
              />
            </template>

            <Space direction="vertical" :size="12" fill>
              <TypographyParagraph type="secondary" :ellipsis="{ rows: 3, expandable: true }">
                {{ item.summary }}
              </TypographyParagraph>
              <Space wrap>
                <Tag :color="statusColor(item.status)">
                  {{ t(`admin.moderationWorkbench.statuses.${item.status}`) }}
                </Tag>
                <Tag :color="riskColor(item.risk_level)">
                  {{ t(`admin.moderationWorkbench.riskLevels.${item.risk_level}`) }}
                </Tag>
                <Tag :color="priorityColor(item.priority)">
                  {{ t(`admin.moderationWorkbench.priorities.${item.priority}`) }}
                </Tag>
              </Space>
              <Descriptions :column="1" bordered size="small">
                <DescriptionsItem :label="t('admin.moderationWorkbench.columns.source')">
                  {{ t(`admin.moderationWorkbench.sourceKinds.${item.source_kind}`) }}
                </DescriptionsItem>
                <DescriptionsItem :label="t('admin.moderationWorkbench.columns.section')">
                  {{ entityLabel(item.section) }}
                </DescriptionsItem>
                <DescriptionsItem :label="t('admin.moderationWorkbench.columns.assignee')">
                  {{ entityLabel(item.assignee) }}
                </DescriptionsItem>
                <DescriptionsItem :label="t('admin.moderationWorkbench.columns.updatedAt')">
                  {{ formatTime(item.updated_at) }}
                </DescriptionsItem>
              </Descriptions>
              <Grid :cols="{ xs: 1, sm: 2 }" :col-gap="8" :row-gap="8">
                <GridItem>
                  <Button long @click="openDetail(item)">
                    {{ t('admin.moderationWorkbench.details.open') }}
                  </Button>
                </GridItem>
                <GridItem v-if="item.available_actions.includes('claim')">
                  <Button
                    type="primary"
                    long
                    :loading="actionLoadingIds.includes(item.id)"
                    @click="claim(item)"
                  >
                    {{ t('admin.moderationWorkbench.actions.claim') }}
                  </Button>
                </GridItem>
              </Grid>
            </Space>
          </Card>
        </Space>

        <Space v-if="rows.length" direction="vertical" :size="8" fill>
          <TypographyText type="secondary">
            {{ t('admin.moderationWorkbench.pagination.total', { count: pagination.count }) }}
          </TypographyText>
          <Pagination
            v-if="pagination.pages > 1"
            :current="pagination.page"
            :total="pagination.count"
            :page-size="pageSize"
            :show-page-size="false"
            simple
            @change="visitPage"
          />
        </Space>
      </Space>
    </Card>

    <Drawer
      v-model:visible="drawerVisible"
      :title="detail?.title || t('admin.moderationWorkbench.details.title')"
      :width="'min(680px, calc(100vw - 16px))'"
      :footer="false"
      unmount-on-close
    >
      <Spin v-if="drawerLoading" :tip="t('admin.moderationWorkbench.details.loading')" />
      <Alert
        v-else-if="detailError && !detail"
        type="error"
        show-icon
        :closable="false"
      >
        {{ detailError }}
      </Alert>
      <Space v-else-if="detail" direction="vertical" :size="16" fill>
        <Alert
          v-if="detailError"
          type="error"
          show-icon
          :closable="false"
        >
          {{ detailError }}
        </Alert>

        <Descriptions :column="1" bordered size="small">
          <DescriptionsItem :label="t('admin.moderationWorkbench.columns.source')">
            {{ t(`admin.moderationWorkbench.sourceKinds.${detail.source_kind}`) }}
          </DescriptionsItem>
          <DescriptionsItem :label="t('admin.moderationWorkbench.columns.status')">
            <Tag :color="statusColor(detail.status)">
              {{ t(`admin.moderationWorkbench.statuses.${detail.status}`) }}
            </Tag>
          </DescriptionsItem>
          <DescriptionsItem :label="t('admin.moderationWorkbench.columns.priority')">
            <Tag :color="priorityColor(detail.priority)">
              {{ t(`admin.moderationWorkbench.priorities.${detail.priority}`) }}
            </Tag>
          </DescriptionsItem>
          <DescriptionsItem :label="t('admin.moderationWorkbench.columns.risk')">
            <Tag :color="riskColor(detail.risk_level)">
              {{ t(`admin.moderationWorkbench.riskLevels.${detail.risk_level}`) }}
            </Tag>
          </DescriptionsItem>
          <DescriptionsItem :label="t('admin.moderationWorkbench.columns.section')">
            {{ entityLabel(detail.section) }}
          </DescriptionsItem>
          <DescriptionsItem :label="t('admin.moderationWorkbench.columns.assignee')">
            {{ entityLabel(detail.assignee) }}
          </DescriptionsItem>
          <DescriptionsItem :label="t('admin.moderationWorkbench.details.claimedAt')">
            {{ formatTime(detail.claimed_at) }}
          </DescriptionsItem>
        </Descriptions>

        <Divider orientation="left">{{ t('admin.moderationWorkbench.details.summary') }}</Divider>
        <TypographyParagraph type="secondary">{{ detail.summary }}</TypographyParagraph>

        <Divider orientation="left">{{ t('admin.moderationWorkbench.details.evidence') }}</Divider>
        <Alert
          v-if="evidenceWasTruncated"
          type="warning"
          show-icon
          :closable="false"
          :title="t('admin.moderationWorkbench.details.evidenceTruncated')"
        />
        <Space v-if="evidenceItems.length" direction="vertical" :size="12" fill>
          <Card
            v-for="(item, index) in evidenceItems"
            :key="index"
            :title="evidenceLabel(item, index)"
            :bordered="true"
            size="small"
          >
            <Textarea
              :model-value="displayEvidence(item)"
              readonly
              :auto-size="{ minRows: 2, maxRows: 12 }"
              :aria-label="evidenceLabel(item, index)"
            />
            <Space v-if="evidenceAttachments(item).length" wrap>
              <Button
                v-for="(attachment, attachmentIndex) in evidenceAttachments(item)"
                :key="attachment.public_id"
                :href="attachment.download_url"
                type="text"
                size="small"
                data-no-prefetch
              >
                {{ t('admin.moderationWorkbench.details.downloadEvidence', { number: attachmentIndex + 1 }) }}
              </Button>
            </Space>
          </Card>
        </Space>
        <Empty v-else :description="t('admin.moderationWorkbench.details.noEvidence')" />

        <template v-if="capabilities.can_assign && detail.available_actions.includes('assign')">
          <Divider orientation="left">{{ t('admin.moderationWorkbench.details.assign') }}</Divider>
          <Grid :cols="{ xs: 1, sm: 3 }" :col-gap="8" :row-gap="8">
            <GridItem :span="{ xs: 1, sm: 2 }">
              <Select
                v-model="assigneeId"
                allow-search
                allow-clear
                :placeholder="t('admin.moderationWorkbench.details.selectAssignee')"
              >
                <Option
                  v-for="option in detail.assignable_staff"
                  :key="optionValue(option)"
                  :value="optionValue(option)"
                >
                  {{ optionLabel(option) }}
                </Option>
              </Select>
            </GridItem>
            <GridItem>
              <Button
                type="primary"
                long
                :loading="assigning"
                :disabled="(assigneeId === '' || assigneeId == null) && !detail.assignee"
                @click="assign"
              >
                {{ assigneeId === '' || assigneeId == null
                  ? detail.assignee
                    ? t('admin.moderationWorkbench.actions.unassign')
                    : t('admin.moderationWorkbench.actions.assign')
                  : t('admin.moderationWorkbench.actions.assign') }}
              </Button>
            </GridItem>
          </Grid>
        </template>

        <Divider orientation="left">{{ t('admin.moderationWorkbench.details.notes') }}</Divider>
        <Space v-if="detail.notes.length" direction="vertical" :size="12" fill>
          <Card
            v-for="(note, index) in detail.notes"
            :key="note.id || index"
            :bordered="true"
            size="small"
          >
            <Space direction="vertical" :size="6" fill>
              <TypographyParagraph>{{ note.body }}</TypographyParagraph>
              <TypographyText type="secondary">
                {{ t('admin.moderationWorkbench.details.noteMeta', {
                  author: noteAuthor(note),
                  time: formatTime(note.created_at),
                }) }}
              </TypographyText>
            </Space>
          </Card>
        </Space>
        <Empty v-else :description="t('admin.moderationWorkbench.details.noNotes')" />

        <Space
          v-if="capabilities.can_note && detail.available_actions.includes('note')"
          direction="vertical"
          :size="8"
          fill
        >
          <Textarea
            v-model="noteBody"
            :placeholder="t('admin.moderationWorkbench.details.notePlaceholder')"
            :auto-size="{ minRows: 3, maxRows: 7 }"
            :max-length="2000"
            show-word-limit
            :disabled="noteSubmitting"
          />
          <Button
            type="primary"
            long
            :loading="noteSubmitting"
            :disabled="noteBody.trim().length === 0"
            @click="addNote"
          >
            {{ t('admin.moderationWorkbench.actions.addNote') }}
          </Button>
        </Space>

        <Divider orientation="left">{{ t('admin.moderationWorkbench.details.actions') }}</Divider>
        <Select
          v-if="detail.available_actions.includes('move_topic')"
          v-model="drawerMoveSectionId"
          :placeholder="t('admin.moderationWorkbench.bulk.destinationSection')"
          allow-search
        >
          <Option
            v-for="option in filter_options.move_sections"
            :key="optionValue(option)"
            :value="optionValue(option)"
          >
            {{ optionLabel(option) }}
          </Option>
        </Select>
        <Space wrap>
          <Button
            v-for="action in detail.available_actions.filter((item) => !['claim', 'assign', 'note'].includes(item))"
            :key="action"
            :status="['delete_content', 'delete_attachment', 'ban_user'].includes(action) ? 'danger' : 'normal'"
            :disabled="action === 'move_topic' && drawerMoveSectionId === ''"
            @click="openAction(action, [detail.id])"
          >
            {{ t(`admin.moderationWorkbench.actions.${action}`) }}
          </Button>
        </Space>
      </Space>
    </Drawer>

    <ModerationActionModal
      v-model:visible="bulkVisible"
      :action="bulkAction"
      :case-ids="selectedCaseIds"
      :attributes="bulkAttributes"
      @completed="handleBulkCompleted"
    />
  </Space>
</template>
