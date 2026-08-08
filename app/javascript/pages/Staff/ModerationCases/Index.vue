<script setup lang="ts">
import { computed, onMounted, reactive, ref, watch } from 'vue'
import { router, usePage } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import {
  Alert,
  Button,
  Card,
  DatePicker,
  Descriptions,
  DescriptionsItem,
  Empty,
  FormItem,
  Grid,
  GridItem,
  Message,
  Modal,
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
import {
  IconCheckCircle,
  IconFilter,
  IconRefresh,
  IconSafe,
} from '@arco-design/web-vue/es/icon'
import StaffLayout from '@/layouts/StaffLayout.vue'
import ModerationActionModal, {
  type ModerationExecutionResponse,
} from '@/components/admin/ModerationActionModal.vue'
import { getJson, HttpError, postJson } from '@/lib/http'

defineOptions({ layout: StaffLayout })

type PrimitiveOption = string | number
type FilterOption =
  | PrimitiveOption
  | {
      value?: PrimitiveOption
      id?: PrimitiveOption
      label?: string
      name?: string
      username?: string
    }

type ModerationCase = {
  id: number
  source_kind: string
  status: string
  priority: string
  risk_level: string
  title: string
  summary: string
  section: { id?: number; name?: string } | null
  assignee: { id?: number; username?: string; name?: string } | null
  claimed_at: string | null
  updated_at: string
  lock_version: number
  available_actions: string[]
}

type Evidence = Record<string, unknown> & {
  restricted?: boolean
  cropped?: boolean
  type?: string
}

type Note = {
  id?: number
  body: string
  author?: { id?: number; username?: string; name?: string } | string | null
  created_at?: string | null
}

type ModerationCaseDetail = ModerationCase & {
  evidence: Evidence | Evidence[] | string | null
  notes: Note[]
  assignable_staff: FilterOption[]
}

type Filters = {
  source_kind: PrimitiveOption | ''
  status: PrimitiveOption | ''
  priority: PrimitiveOption | ''
  risk_level: PrimitiveOption | ''
  section_id: PrimitiveOption | ''
  assignee_id: PrimitiveOption | ''
  from: string
  to: string
}

const props = defineProps<{
  cases: ModerationCase[]
  pagination: { page: number; pages: number; count: number }
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
    can_execute: boolean
  }
  endpoints: {
    index: string
    authorize_action: string
    execute_action: string
  }
  sync_warning?: string | null
}>()

const page = usePage()
const { locale, t } = useI18n()
const rows = ref<ModerationCase[]>([...props.cases])
const filters = reactive<Filters>({
  source_kind: props.filters.source_kind || '',
  status: props.filters.status || '',
  priority: props.filters.priority || '',
  risk_level: props.filters.risk_level || '',
  section_id: props.filters.section_id || '',
  assignee_id: props.filters.assignee_id || '',
  from: props.filters.from || '',
  to: props.filters.to || '',
})
const selectedCaseIds = ref<number[]>([])
const pageError = ref('')
const detailVisible = ref(false)
const detailLoading = ref(false)
const detail = ref<ModerationCaseDetail | null>(null)
const detailError = ref('')
const assigneeId = ref<PrimitiveOption | ''>('')
const assigning = ref(false)
const noteBody = ref('')
const noteSubmitting = ref(false)
const actionVisible = ref(false)
const actionName = ref('')
const actionCaseIds = ref<number[]>([])
const moveSectionId = ref<PrimitiveOption | ''>('')
const rowLoadingIds = ref<number[]>([])

const rowSelection = {
  type: 'checkbox' as const,
  showCheckedAll: true,
  onlyCurrent: true,
  width: 48,
}

watch(
  () => props.cases,
  (value) => {
    rows.value = [...value]
    const ids = new Set(value.map((item) => item.id))
    selectedCaseIds.value = selectedCaseIds.value.filter((id) => ids.has(id))
  },
)

watch(
  () => props.filters,
  (value) => {
    Object.assign(filters, {
      source_kind: value.source_kind || '',
      status: value.status || '',
      priority: value.priority || '',
      risk_level: value.risk_level || '',
      section_id: value.section_id || '',
      assignee_id: value.assignee_id || '',
      from: value.from || '',
      to: value.to || '',
    })
  },
)

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
const detailActions = computed(() =>
  (detail.value?.available_actions || []).filter(
    (action) => !['claim', 'assign', 'note'].includes(action),
  ),
)
const activeFilterCount = computed(() =>
  Object.values(filters).filter((value) => value !== '').length,
)
const actionAttributes = computed<Record<string, unknown>>(() =>
  actionName.value === 'move_topic' && moveSectionId.value !== ''
    ? { section_id: moveSectionId.value }
    : {},
)

function optionValue(option: FilterOption): PrimitiveOption {
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
  return namespace ? t(`${namespace}.${value}`) : String(value)
}

function formatTime(value?: string | null) {
  if (!value) return t('staffWorkspace.notAvailable')
  return new Intl.DateTimeFormat(locale.value, {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(value))
}

function entityLabel(value: ModerationCase['section'] | ModerationCase['assignee']) {
  return value?.name || value?.username || t('staffWorkspace.unassigned')
}

function statusColor(value: string) {
  if (['resolved', 'actioned'].includes(value)) return 'green'
  if (value === 'dismissed') return 'gray'
  if (value === 'claimed') return 'arcoblue'
  return 'orange'
}

function riskColor(value: string) {
  if (['critical', 'high'].includes(value)) return 'red'
  if (value === 'medium') return 'orange'
  return 'blue'
}

function errorText(error: unknown) {
  if (error instanceof HttpError && error.body && typeof error.body === 'object') {
    const body = error.body as { error?: unknown; message?: unknown }
    if (typeof body.error === 'string' && body.error) return body.error
    if (typeof body.message === 'string' && body.message) return body.message
  }
  return t('staffWorkspace.requestFailed')
}

function query(pageNumber = 1) {
  return Object.fromEntries(
    Object.entries({ ...filters, page: pageNumber }).filter(([, value]) => value !== ''),
  )
}

function applyFilters() {
  router.get(props.endpoints.index, query(), {
    preserveState: true,
    preserveScroll: true,
    replace: true,
  })
}

function clearFilters() {
  Object.assign(filters, {
    source_kind: '',
    status: '',
    priority: '',
    risk_level: '',
    section_id: '',
    assignee_id: '',
    from: '',
    to: '',
  })
  applyFilters()
}

function visitPage(pageNumber: number) {
  router.get(props.endpoints.index, query(pageNumber), {
    preserveState: true,
    preserveScroll: true,
    replace: true,
  })
}

function replaceCase(updated: ModerationCase) {
  const index = rows.value.findIndex((item) => item.id === updated.id)
  if (index >= 0) rows.value.splice(index, 1, { ...rows.value[index], ...updated })
  if (detail.value?.id === updated.id) detail.value = { ...detail.value, ...updated }
}

async function loadDetail(id: number) {
  detailLoading.value = true
  detailError.value = ''
  try {
    const response = await getJson<{ case: ModerationCaseDetail }>(
      `${props.endpoints.index}/${id}`,
    )
    detail.value = response.case
    assigneeId.value =
      typeof response.case.assignee === 'object' && response.case.assignee?.id
        ? response.case.assignee.id
        : ''
  } catch (error) {
    detailError.value = errorText(error)
  } finally {
    detailLoading.value = false
  }
}

function openDetail(item: ModerationCase) {
  detail.value = null
  detailError.value = ''
  noteBody.value = ''
  assigneeId.value = ''
  actionName.value = ''
  moveSectionId.value = ''
  detailVisible.value = true
  void loadDetail(item.id)
}

async function claim(item: ModerationCase) {
  if (!item.available_actions.includes('claim')) return
  rowLoadingIds.value.push(item.id)
  pageError.value = ''
  try {
    const response = await postJson<{ case: ModerationCase }>(
      `${props.endpoints.index}/${item.id}/claim`,
      { lock_version: item.lock_version },
    )
    replaceCase(response.case)
    Message.success(t('staffWorkspace.claimed'))
  } catch (error) {
    pageError.value = errorText(error)
  } finally {
    rowLoadingIds.value = rowLoadingIds.value.filter((id) => id !== item.id)
  }
}

async function assign() {
  if (!detail.value || !props.capabilities.can_assign) return
  assigning.value = true
  detailError.value = ''
  try {
    const response = await postJson<{ case: ModerationCaseDetail }>(
      `${props.endpoints.index}/${detail.value.id}/assign`,
      {
        lock_version: detail.value.lock_version,
        assignee_id: assigneeId.value === '' ? null : assigneeId.value,
      },
    )
    detail.value = response.case
    replaceCase(response.case)
    Message.success(t('staffWorkspace.assigned'))
  } catch (error) {
    detailError.value = errorText(error)
  } finally {
    assigning.value = false
  }
}

async function addNote() {
  if (!detail.value || !noteBody.value.trim()) return
  noteSubmitting.value = true
  detailError.value = ''
  try {
    const response = await postJson<{ case: ModerationCaseDetail }>(
      `${props.endpoints.index}/${detail.value.id}/notes`,
      {
        lock_version: detail.value.lock_version,
        body: noteBody.value.trim(),
      },
    )
    detail.value = response.case
    replaceCase(response.case)
    noteBody.value = ''
    Message.success(t('staffWorkspace.noteAdded'))
  } catch (error) {
    detailError.value = errorText(error)
  } finally {
    noteSubmitting.value = false
  }
}

function openAction(caseIds: number[], action: string) {
  if (!caseIds.length || !action) return
  if (action === 'move_topic' && moveSectionId.value === '') return
  actionCaseIds.value = [...caseIds]
  actionName.value = action
  actionVisible.value = true
}

function openBulkAction() {
  openAction(selectedCaseIds.value, actionName.value)
}

function openDetailAction() {
  if (!detail.value) return
  openAction([detail.value.id], actionName.value)
}

function actionCompleted(_result: ModerationExecutionResponse) {
  selectedCaseIds.value = []
  actionName.value = ''
  moveSectionId.value = ''
  router.reload({ only: ['cases', 'pagination'], preserveScroll: true })
  if (detail.value && detailVisible.value) void loadDetail(detail.value.id)
}

function evidenceEntries() {
  const value = detail.value?.evidence
  if (!value) return []
  if (typeof value === 'string') return [['content', value]]
  if (Array.isArray(value)) return [['items', value]]
  return Object.entries(value)
}

function displayValue(value: unknown) {
  if (value === null || value === undefined || value === '') {
    return t('staffWorkspace.notAvailable')
  }
  if (typeof value === 'object') return JSON.stringify(value, null, 2)
  return String(value)
}

function noteAuthor(note: Note) {
  if (typeof note.author === 'string') return note.author
  return note.author?.name || note.author?.username || t('staffWorkspace.notAvailable')
}

onMounted(() => {
  const search = page.url.split('?')[1]
  if (!search) return
  const id = Number(new URLSearchParams(search).get('case_id'))
  const item = rows.value.find((record) => record.id === id)
  if (item) openDetail(item)
})
</script>

<template>
  <Space direction="vertical" fill size="large">
    <PageHeader
      :show-back="false"
      :title="t('staffWorkspace.cases.pageTitle')"
      :subtitle="t('staffWorkspace.cases.pageSubtitle')"
    >
      <template #extra>
        <Button shape="round" @click="router.reload({ preserveScroll: true })">
          <template #icon><IconRefresh /></template>
          {{ t('common.refresh') }}
        </Button>
      </template>
    </PageHeader>

    <Alert v-if="sync_warning" type="warning" show-icon>
      {{ t('staffWorkspace.syncWarning') }}
    </Alert>
    <Alert v-if="pageError" type="error" show-icon closable @close="pageError = ''">
      {{ pageError }}
    </Alert>

    <Card :bordered="true" :style="{ borderRadius: '14px' }">
      <template #title>
        <Space align="center">
          <IconFilter />
          <span>{{ t('staffWorkspace.filters.title') }}</span>
          <Tag v-if="activeFilterCount" color="arcoblue">{{ activeFilterCount }}</Tag>
        </Space>
      </template>
      <Grid :cols="{ xs: 1, sm: 2, lg: 4 }" :col-gap="10" :row-gap="10">
        <GridItem>
          <Select v-model="filters.source_kind" allow-clear :placeholder="t('staffWorkspace.filters.source')">
            <Option
              v-for="option in filter_options.source_kinds"
              :key="optionValue(option)"
              :value="optionValue(option)"
            >
              {{ optionLabel(option, 'staffWorkspace.sourceKinds') }}
            </Option>
          </Select>
        </GridItem>
        <GridItem>
          <Select v-model="filters.status" allow-clear :placeholder="t('staffWorkspace.filters.status')">
            <Option
              v-for="option in filter_options.statuses"
              :key="optionValue(option)"
              :value="optionValue(option)"
            >
              {{ optionLabel(option, 'staffWorkspace.statuses') }}
            </Option>
          </Select>
        </GridItem>
        <GridItem>
          <Select v-model="filters.priority" allow-clear :placeholder="t('staffWorkspace.filters.priority')">
            <Option
              v-for="option in filter_options.priorities"
              :key="optionValue(option)"
              :value="optionValue(option)"
            >
              {{ optionLabel(option, 'staffWorkspace.priorities') }}
            </Option>
          </Select>
        </GridItem>
        <GridItem>
          <Select v-model="filters.risk_level" allow-clear :placeholder="t('staffWorkspace.filters.risk')">
            <Option
              v-for="option in filter_options.risk_levels"
              :key="optionValue(option)"
              :value="optionValue(option)"
            >
              {{ optionLabel(option, 'staffWorkspace.riskLevels') }}
            </Option>
          </Select>
        </GridItem>
        <GridItem>
          <Select v-model="filters.section_id" allow-clear :placeholder="t('staffWorkspace.filters.section')">
            <Option
              v-for="option in filter_options.sections"
              :key="optionValue(option)"
              :value="optionValue(option)"
            >
              {{ optionLabel(option) }}
            </Option>
          </Select>
        </GridItem>
        <GridItem>
          <Select v-model="filters.assignee_id" allow-clear :placeholder="t('staffWorkspace.filters.assignee')">
            <Option value="me">{{ t('staffWorkspace.filters.me') }}</Option>
            <Option value="unassigned">{{ t('staffWorkspace.unassigned') }}</Option>
            <Option
              v-for="option in filter_options.staff"
              :key="optionValue(option)"
              :value="optionValue(option)"
            >
              {{ optionLabel(option) }}
            </Option>
          </Select>
        </GridItem>
        <GridItem>
          <DatePicker
            v-model="filters.from"
            value-format="YYYY-MM-DD"
            :placeholder="t('staffWorkspace.filters.from')"
            allow-clear
          />
        </GridItem>
        <GridItem>
          <DatePicker
            v-model="filters.to"
            value-format="YYYY-MM-DD"
            :placeholder="t('staffWorkspace.filters.to')"
            allow-clear
          />
        </GridItem>
        <GridItem :span="{ xs: 1, sm: 2 }">
          <Space wrap>
            <Button type="primary" @click="applyFilters">{{ t('staffWorkspace.filters.apply') }}</Button>
            <Button @click="clearFilters">{{ t('staffWorkspace.filters.clear') }}</Button>
          </Space>
        </GridItem>
      </Grid>
    </Card>

    <Card :bordered="true" :style="{ borderRadius: '8px' }">
      <template #title>
        {{ t('staffWorkspace.cases.queueCount', { count: pagination.count }) }}
      </template>
      <template #extra>
        <Space v-if="selectedCaseIds.length" wrap>
          <Tag color="arcoblue">
            {{ t('staffWorkspace.cases.selected', { count: selectedCaseIds.length }) }}
          </Tag>
          <Select
            v-model="actionName"
            :placeholder="t('staffWorkspace.cases.chooseAction')"
            :style="{ width: '210px' }"
          >
            <Option v-for="action in commonActions" :key="action" :value="action">
              {{ t(`admin.moderationWorkbench.actions.${action}`) }}
            </Option>
          </Select>
          <Select
            v-if="actionName === 'move_topic'"
            v-model="moveSectionId"
            :placeholder="t('staffWorkspace.cases.destination')"
            :style="{ width: '220px' }"
          >
            <Option
              v-for="option in filter_options.move_sections"
              :key="optionValue(option)"
              :value="optionValue(option)"
            >
              {{ optionLabel(option) }}
            </Option>
          </Select>
          <Button
            type="primary"
            status="warning"
            :disabled="!actionName || (actionName === 'move_topic' && moveSectionId === '')"
            @click="openBulkAction"
          >
            {{ t('staffWorkspace.cases.reviewAction') }}
          </Button>
        </Space>
      </template>

      <Table
        v-model:selected-keys="selectedCaseIds"
        :data="rows"
        :pagination="false"
        :row-selection="rowSelection"
        row-key="id"
        :bordered="{ wrapper: true }"
        :scroll="{ minWidth: 1120 }"
        @row-click="openDetail"
      >
        <template #columns>
          <TableColumn :title="t('staffWorkspace.cases.case')" :width="88">
            <template #cell="{ record }">#{{ record.id }}</template>
          </TableColumn>
          <TableColumn :title="t('staffWorkspace.cases.title')" :width="280">
            <template #cell="{ record }">
              <Space direction="vertical" :size="2">
                <TypographyText bold>{{ record.title }}</TypographyText>
                <TypographyText type="secondary" ellipsis>{{ record.summary }}</TypographyText>
              </Space>
            </template>
          </TableColumn>
          <TableColumn :title="t('staffWorkspace.cases.source')" :width="150">
            <template #cell="{ record }">
              {{ t(`staffWorkspace.sourceKinds.${record.source_kind}`) }}
            </template>
          </TableColumn>
          <TableColumn :title="t('staffWorkspace.cases.status')" :width="120">
            <template #cell="{ record }">
              <Tag :color="statusColor(record.status)">
                {{ t(`staffWorkspace.statuses.${record.status}`) }}
              </Tag>
            </template>
          </TableColumn>
          <TableColumn :title="t('staffWorkspace.cases.risk')" :width="110">
            <template #cell="{ record }">
              <Tag :color="riskColor(record.risk_level)">
                {{ t(`staffWorkspace.riskLevels.${record.risk_level}`) }}
              </Tag>
            </template>
          </TableColumn>
          <TableColumn :title="t('staffWorkspace.cases.section')" :width="160">
            <template #cell="{ record }">{{ entityLabel(record.section) }}</template>
          </TableColumn>
          <TableColumn :title="t('staffWorkspace.cases.assignee')" :width="160">
            <template #cell="{ record }">{{ entityLabel(record.assignee) }}</template>
          </TableColumn>
          <TableColumn :title="t('staffWorkspace.cases.actions')" :width="150" fixed="right">
            <template #cell="{ record }">
              <Space>
                <Button size="small" @click.stop="openDetail(record)">
                  {{ t('staffWorkspace.cases.open') }}
                </Button>
                <Button
                  v-if="record.available_actions.includes('claim')"
                  type="primary"
                  size="small"
                  :loading="rowLoadingIds.includes(record.id)"
                  @click.stop="claim(record)"
                >
                  {{ t('staffWorkspace.cases.claim') }}
                </Button>
              </Space>
            </template>
          </TableColumn>
        </template>
        <template #empty>
          <Empty :description="t('staffWorkspace.cases.empty')" />
        </template>
      </Table>

      <Pagination
        v-if="pagination.pages > 1"
        :current="pagination.page"
        :total="pagination.count"
        :page-size="30"
        show-total
        :style="{ marginTop: '16px', justifyContent: 'flex-end' }"
        @change="visitPage"
      />
    </Card>

    <Modal
      v-model:visible="detailVisible"
      :title="detail ? `#${detail.id} · ${detail.title}` : t('staffWorkspace.cases.detail')"
      :footer="false"
      :width="'min(920px, calc(100vw - 24px))'"
      align-center
      unmount-on-close
    >
      <Spin :loading="detailLoading" tip="">
        <Alert v-if="detailError" type="error" show-icon>{{ detailError }}</Alert>
        <Space v-if="detail" direction="vertical" fill size="large">
          <Descriptions :column="2" bordered size="small">
            <DescriptionsItem :label="t('staffWorkspace.cases.status')">
              <Tag :color="statusColor(detail.status)">
                {{ t(`staffWorkspace.statuses.${detail.status}`) }}
              </Tag>
            </DescriptionsItem>
            <DescriptionsItem :label="t('staffWorkspace.cases.risk')">
              <Tag :color="riskColor(detail.risk_level)">
                {{ t(`staffWorkspace.riskLevels.${detail.risk_level}`) }}
              </Tag>
            </DescriptionsItem>
            <DescriptionsItem :label="t('staffWorkspace.cases.section')">
              {{ entityLabel(detail.section) }}
            </DescriptionsItem>
            <DescriptionsItem :label="t('staffWorkspace.cases.updated')">
              {{ formatTime(detail.updated_at) }}
            </DescriptionsItem>
          </Descriptions>

          <Card :bordered="true" size="small">
            <template #title>{{ t('staffWorkspace.cases.evidence') }}</template>
            <Alert
              v-if="typeof detail.evidence === 'object' && !Array.isArray(detail.evidence) && detail.evidence?.restricted"
              type="warning"
              show-icon
            >
              {{ t('staffWorkspace.cases.evidenceRestricted') }}
            </Alert>
            <Descriptions v-else :column="1" bordered size="small">
              <DescriptionsItem v-for="[key, value] in evidenceEntries()" :key="key" :label="key">
                <TypographyParagraph
                  :style="{ margin: 0, whiteSpace: 'pre-wrap', wordBreak: 'break-word' }"
                >
                  {{ displayValue(value) }}
                </TypographyParagraph>
              </DescriptionsItem>
            </Descriptions>
          </Card>

          <Grid :cols="{ xs: 1, md: 2 }" :col-gap="12" :row-gap="12">
            <GridItem>
              <Card :bordered="true" size="small">
                <template #title>{{ t('staffWorkspace.cases.assignment') }}</template>
                <Space direction="vertical" fill>
                  <Select v-model="assigneeId" allow-clear>
                    <Option value="">{{ t('staffWorkspace.unassigned') }}</Option>
                    <Option
                      v-for="option in detail.assignable_staff"
                      :key="optionValue(option)"
                      :value="optionValue(option)"
                    >
                      {{ optionLabel(option) }}
                    </Option>
                  </Select>
                  <Button
                    type="primary"
                    :loading="assigning"
                    :disabled="!capabilities.can_assign"
                    @click="assign"
                  >
                    {{ t('staffWorkspace.cases.saveAssignment') }}
                  </Button>
                </Space>
              </Card>
            </GridItem>

            <GridItem>
              <Card :bordered="true" size="small">
                <template #title>{{ t('staffWorkspace.cases.action') }}</template>
                <Space direction="vertical" fill>
                  <Select v-model="actionName" :placeholder="t('staffWorkspace.cases.chooseAction')">
                    <Option v-for="action in detailActions" :key="action" :value="action">
                      {{ t(`admin.moderationWorkbench.actions.${action}`) }}
                    </Option>
                  </Select>
                  <Select
                    v-if="actionName === 'move_topic'"
                    v-model="moveSectionId"
                    :placeholder="t('staffWorkspace.cases.destination')"
                  >
                    <Option
                      v-for="option in filter_options.move_sections"
                      :key="optionValue(option)"
                      :value="optionValue(option)"
                    >
                      {{ optionLabel(option) }}
                    </Option>
                  </Select>
                  <Button
                    type="primary"
                    status="warning"
                    :disabled="!actionName || (actionName === 'move_topic' && moveSectionId === '')"
                    @click="openDetailAction"
                  >
                    {{ t('staffWorkspace.cases.reviewAction') }}
                  </Button>
                </Space>
              </Card>
            </GridItem>
          </Grid>

          <Card :bordered="true" size="small">
            <template #title>{{ t('staffWorkspace.cases.notes') }}</template>
            <Space direction="vertical" fill>
              <Card v-for="note in detail.notes" :key="note.id || note.created_at" size="small" :bordered="true">
                <TypographyParagraph :style="{ marginBottom: '6px' }">{{ note.body }}</TypographyParagraph>
                <TypographyText type="secondary">
                  {{ noteAuthor(note) }} · {{ formatTime(note.created_at) }}
                </TypographyText>
              </Card>
              <Empty v-if="!detail.notes.length" :description="t('staffWorkspace.cases.noNotes')" />
              <FormItem :label="t('staffWorkspace.cases.addNote')">
                <Textarea
                  v-model="noteBody"
                  :auto-size="{ minRows: 3, maxRows: 6 }"
                  :max-length="2000"
                  show-word-limit
                />
              </FormItem>
              <Button
                type="primary"
                :loading="noteSubmitting"
                :disabled="!noteBody.trim() || !capabilities.can_note"
                @click="addNote"
              >
                <template #icon><IconCheckCircle /></template>
                {{ t('staffWorkspace.cases.submitNote') }}
              </Button>
            </Space>
          </Card>
        </Space>
      </Spin>
    </Modal>

    <ModerationActionModal
      v-model:visible="actionVisible"
      :action="actionName"
      :case-ids="actionCaseIds"
      :attributes="actionAttributes"
      :authorize-url="endpoints.authorize_action"
      :execute-url="endpoints.execute_action"
      @completed="actionCompleted"
    />
  </Space>
</template>
