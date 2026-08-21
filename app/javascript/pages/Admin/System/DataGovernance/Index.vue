<script setup lang="ts">
import { computed, reactive, ref } from 'vue'
import { router } from '@inertiajs/vue3'
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
  InputNumber,
  Message,
  Modal,
  Option,
  PageHeader,
  Select,
  Space,
  Statistic,
  Switch,
  Table,
  TableColumn,
  TabPane,
  Tabs,
  Tag,
  Textarea,
  TypographyText,
} from '@mcweb/ui'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { HttpError, postJson } from '@/lib/http'

defineOptions({ layout: AdminLayout })

type Actor = { username: string; publicId: string } | null

type Policy = {
  id: number
  resourceType: string
  resourceLabel: string
  retentionDays: number | null
  userDeletable: boolean
  moderatorRestorable: boolean
  legalHoldSupported: boolean
  notes: string | null
  activeHolds: number
  awaitingPurge: number
}

type LifecycleRecord = {
  id: string
  targetType: string
  targetLabel: string
  targetReference: string
  status: 'soft_deleted' | 'restored' | 'purged'
  softDeletedAt: string | null
  purgeAfter: string | null
  restoredAt: string | null
  purgedAt: string | null
  deletionReason: string
  restorationReason: string | null
  purgeReason: string | null
  blockerCodes: string[]
  purgeAttempts: number
  actors: {
    deletedBy: Actor
    restoredBy: Actor
    purgedBy: Actor
  }
}

type Hold = {
  id: string
  targetType: string
  targetLabel: string
  targetReference: string
  status: 'active' | 'released'
  effective: boolean
  reason: string
  policyReference: string | null
  expiresAt: string | null
  releasedAt: string | null
  releaseReason: string | null
  createdAt: string
  createdBy: Actor
  releasedBy: Actor
}

const props = defineProps<{
  policies: Policy[]
  records: LifecycleRecord[]
  holds: Hold[]
  resourceTypes: Array<{ value: string; label: string }>
  summary: {
    policies: number
    activeHolds: number
    awaitingPurge: number
    blocked: number
  }
  permissions: {
    managePolicies: boolean
    manageHolds: boolean
    softDelete: boolean
    restore: boolean
    purge: boolean
  }
  paths: {
    policy: string
    createHold: string
    releaseHold: string
    softDelete: string
    restore: string
    purge: string
  }
}>()

const { t, locale } = useI18n()
const activeTab = ref('lifecycle')
const selectedPolicy = ref<Policy | null>(null)
const selectedRecord = ref<LifecycleRecord | null>(null)
const policySubmitting = ref(false)
const actionSubmitting = ref(false)
const createHoldVisible = ref(false)
const softDeleteVisible = ref(false)
const releaseHoldTarget = ref<Hold | null>(null)
const lifecycleAction = ref<{ action: 'restore' | 'purge'; record: LifecycleRecord } | null>(null)

const policyForm = reactive({
  retentionDays: null as number | null,
  userDeletable: true,
  moderatorRestorable: true,
  legalHoldSupported: true,
  notes: '',
  reason: '',
})
const targetForm = reactive({
  targetType: '',
  targetReference: '',
  reason: '',
  policyReference: '',
  expiresAt: '',
})
const actionReason = ref('')

const policyDrawerVisible = computed({
  get: () => selectedPolicy.value !== null,
  set: (visible: boolean) => {
    if (!visible && !policySubmitting.value) selectedPolicy.value = null
  },
})
const recordDrawerVisible = computed({
  get: () => selectedRecord.value !== null,
  set: (visible: boolean) => {
    if (!visible) selectedRecord.value = null
  },
})
const releaseHoldVisible = computed({
  get: () => releaseHoldTarget.value !== null,
  set: (visible: boolean) => {
    if (!visible && !actionSubmitting.value) {
      releaseHoldTarget.value = null
      actionReason.value = ''
    }
  },
})
const lifecycleActionVisible = computed({
  get: () => lifecycleAction.value !== null,
  set: (visible: boolean) => {
    if (!visible && !actionSubmitting.value) {
      lifecycleAction.value = null
      actionReason.value = ''
    }
  },
})
const resourceTypeLabels = computed(
  () => new Map(props.resourceTypes.map((entry) => [entry.value, entry.label])),
)

function pathFor(template: string, id: string | number) {
  return template.replace('__ID__', encodeURIComponent(String(id)))
}

function resourceTypeLabel(resourceType: string) {
  return resourceTypeLabels.value.get(resourceType) || resourceType
}

function formatDate(value: string | null) {
  if (!value) return t('admin.dataGovernance.notScheduled')
  return new Intl.DateTimeFormat(locale.value, {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(value))
}

function statusColor(status: string) {
  if (status === 'soft_deleted' || status === 'active') return 'orange'
  if (status === 'purged') return 'red'
  return 'green'
}

function errorMessage(error: unknown) {
  if (error instanceof HttpError && error.body && typeof error.body === 'object') {
    const body = error.body as { error?: string; blockers?: string[] }
    if (body.blockers?.length) {
      return t('admin.dataGovernance.errors.blockedWithReasons', {
        reasons: body.blockers.map(blockerLabel).join(', '),
      })
    }
    if (body.error) {
      return t(`admin.dataGovernance.errors.${body.error}`, body.error)
    }
  }
  return t('admin.dataGovernance.errors.requestFailed')
}

function blockerLabel(code: string) {
  return t(`admin.dataGovernance.blockers.${code}`, code)
}

function reloadWorkspace() {
  router.reload({
    only: ['policies', 'records', 'holds', 'summary'],
    preserveScroll: true,
    preserveState: true,
  })
}

function openPolicy(policy: Policy) {
  selectedPolicy.value = policy
  Object.assign(policyForm, {
    retentionDays: policy.retentionDays,
    userDeletable: policy.userDeletable,
    moderatorRestorable: policy.moderatorRestorable,
    legalHoldSupported: policy.legalHoldSupported,
    notes: policy.notes || '',
    reason: '',
  })
}

async function savePolicy() {
  if (!selectedPolicy.value) return
  policySubmitting.value = true
  try {
    await postJson(pathFor(props.paths.policy, selectedPolicy.value.id), {
      retention_days: policyForm.retentionDays,
      user_deletable: policyForm.userDeletable,
      moderator_restorable: policyForm.moderatorRestorable,
      legal_hold_supported: policyForm.legalHoldSupported,
      notes: policyForm.notes,
      reason: policyForm.reason,
    }, { method: 'PATCH' })
    Message.success(t('admin.dataGovernance.messages.policyUpdated'))
    selectedPolicy.value = null
    reloadWorkspace()
  } catch (error) {
    Message.error(errorMessage(error))
  } finally {
    policySubmitting.value = false
  }
}

function resetTargetForm() {
  Object.assign(targetForm, {
    targetType: props.resourceTypes[0]?.value || '',
    targetReference: '',
    reason: '',
    policyReference: '',
    expiresAt: '',
  })
}

function openCreateHold() {
  resetTargetForm()
  createHoldVisible.value = true
}

function openSoftDelete() {
  resetTargetForm()
  softDeleteVisible.value = true
}

async function createHold() {
  actionSubmitting.value = true
  try {
    await postJson(props.paths.createHold, {
      target_type: targetForm.targetType,
      target_reference: targetForm.targetReference,
      reason: targetForm.reason,
      policy_reference: targetForm.policyReference,
      expires_at: targetForm.expiresAt || null,
    })
    Message.success(t('admin.dataGovernance.messages.holdPlaced'))
    createHoldVisible.value = false
    reloadWorkspace()
  } catch (error) {
    Message.error(errorMessage(error))
  } finally {
    actionSubmitting.value = false
  }
}

async function softDelete() {
  actionSubmitting.value = true
  try {
    await postJson(props.paths.softDelete, {
      target_type: targetForm.targetType,
      target_reference: targetForm.targetReference,
      reason: targetForm.reason,
    })
    Message.success(t('admin.dataGovernance.messages.softDeleted'))
    softDeleteVisible.value = false
    reloadWorkspace()
  } catch (error) {
    Message.error(errorMessage(error))
  } finally {
    actionSubmitting.value = false
  }
}

async function releaseHold() {
  if (!releaseHoldTarget.value) return
  actionSubmitting.value = true
  try {
    await postJson(pathFor(props.paths.releaseHold, releaseHoldTarget.value.id), {
      reason: actionReason.value,
    }, { method: 'PATCH' })
    Message.success(t('admin.dataGovernance.messages.holdReleased'))
    releaseHoldTarget.value = null
    actionReason.value = ''
    reloadWorkspace()
  } catch (error) {
    Message.error(errorMessage(error))
  } finally {
    actionSubmitting.value = false
  }
}

function openLifecycleAction(action: 'restore' | 'purge', record: LifecycleRecord) {
  actionReason.value = ''
  lifecycleAction.value = { action, record }
}

async function executeLifecycleAction() {
  if (!lifecycleAction.value) return
  const { action, record } = lifecycleAction.value
  actionSubmitting.value = true
  try {
    const path = pathFor(action === 'restore' ? props.paths.restore : props.paths.purge, record.id)
    await postJson(path, { reason: actionReason.value }, {
      method: action === 'restore' ? 'PATCH' : 'DELETE',
    })
    Message.success(t(`admin.dataGovernance.messages.${action === 'restore' ? 'restored' : 'purged'}`))
    lifecycleAction.value = null
    selectedRecord.value = null
    actionReason.value = ''
    reloadWorkspace()
  } catch (error) {
    Message.error(errorMessage(error))
  } finally {
    actionSubmitting.value = false
  }
}
</script>

<template>
  <PageHeader
    :title="t('admin.dataGovernance.title')"
    :subtitle="t('admin.dataGovernance.subtitle')"
  >
    <template #extra>
      <Space>
        <Button v-if="permissions.manageHolds" @click="openCreateHold">
          {{ t('admin.dataGovernance.actions.placeHold') }}
        </Button>
        <Button v-if="permissions.softDelete" type="primary" @click="openSoftDelete">
          {{ t('admin.dataGovernance.actions.softDelete') }}
        </Button>
      </Space>
    </template>
  </PageHeader>

  <Space direction="vertical" size="large" fill>
    <Alert
      type="info"
      show-icon
      :closable="false"
      :title="t('admin.dataGovernance.safetyTitle')"
    >
      {{ t('admin.dataGovernance.safetyDescription') }}
    </Alert>

    <Grid :cols="{ xs: 1, sm: 2, xl: 4 }" :col-gap="16" :row-gap="16">
      <GridItem>
        <Card :bordered="false">
          <Statistic :title="t('admin.dataGovernance.metrics.policies')" :value="summary.policies" />
        </Card>
      </GridItem>
      <GridItem>
        <Card :bordered="false">
          <Statistic :title="t('admin.dataGovernance.metrics.activeHolds')" :value="summary.activeHolds" />
        </Card>
      </GridItem>
      <GridItem>
        <Card :bordered="false">
          <Statistic :title="t('admin.dataGovernance.metrics.awaitingPurge')" :value="summary.awaitingPurge" />
        </Card>
      </GridItem>
      <GridItem>
        <Card :bordered="false">
          <Statistic :title="t('admin.dataGovernance.metrics.blocked')" :value="summary.blocked" />
        </Card>
      </GridItem>
    </Grid>

    <Card :bordered="false">
      <Tabs v-model:active-key="activeTab" type="rounded">
        <TabPane key="lifecycle" :title="t('admin.dataGovernance.tabs.lifecycle')">
            <Table
              :data="records"
              row-key="id"
              :pagination="false"
              :bordered="false"
              :scroll="{ x: 1240 }"
            >
              <template #empty>
                <Empty :description="t('admin.dataGovernance.empty.lifecycle')" />
              </template>
              <TableColumn :title="t('admin.dataGovernance.columns.content')" :width="260">
                <template #cell="{ record }">
                  <Button type="text" @click="selectedRecord = record">
                    {{ record.targetLabel }}
                  </Button>
                  <div>
                    <TypographyText type="secondary">
                      {{ record.targetReference }}
                    </TypographyText>
                  </div>
                </template>
              </TableColumn>
              <TableColumn :title="t('admin.dataGovernance.columns.resourceType')" :width="190">
                <template #cell="{ record }">{{ resourceTypeLabel(record.targetType) }}</template>
              </TableColumn>
              <TableColumn :title="t('admin.dataGovernance.columns.status')" :width="130">
                <template #cell="{ record }">
                  <Tag :color="statusColor(record.status)">
                    {{ t(`admin.dataGovernance.statuses.${record.status}`) }}
                  </Tag>
                </template>
              </TableColumn>
              <TableColumn :title="t('admin.dataGovernance.columns.purgeAfter')" :width="190">
                <template #cell="{ record }">{{ formatDate(record.purgeAfter) }}</template>
              </TableColumn>
              <TableColumn :title="t('admin.dataGovernance.columns.blockers')" :width="240">
                <template #cell="{ record }">
                  <Space v-if="record.blockerCodes.length" wrap>
                    <Tag v-for="code in record.blockerCodes" :key="code" color="red">
                      {{ blockerLabel(code) }}
                    </Tag>
                  </Space>
                  <TypographyText v-else type="secondary">
                    {{ t('admin.dataGovernance.noBlockers') }}
                  </TypographyText>
                </template>
              </TableColumn>
              <TableColumn :title="t('admin.dataGovernance.columns.actions')" fixed="right" :width="180">
                <template #cell="{ record }">
                  <Space>
                    <Button
                      v-if="permissions.restore && record.status === 'soft_deleted'"
                      size="small"
                      @click="openLifecycleAction('restore', record)"
                    >
                      {{ t('admin.dataGovernance.actions.restore') }}
                    </Button>
                    <Button
                      v-if="permissions.purge && record.status === 'soft_deleted'"
                      size="small"
                      status="danger"
                      @click="openLifecycleAction('purge', record)"
                    >
                      {{ t('admin.dataGovernance.actions.purge') }}
                    </Button>
                  </Space>
                </template>
              </TableColumn>
            </Table>
        </TabPane>

        <TabPane key="holds" :title="t('admin.dataGovernance.tabs.holds')">
            <Table
              :data="holds"
              row-key="id"
              :pagination="false"
              :bordered="false"
              :scroll="{ x: 1230 }"
            >
              <template #empty>
                <Empty :description="t('admin.dataGovernance.empty.holds')" />
              </template>
              <TableColumn :title="t('admin.dataGovernance.columns.content')" :width="260">
                <template #cell="{ record }">
                  <strong>{{ record.targetLabel }}</strong>
                  <div><TypographyText type="secondary">{{ record.targetReference }}</TypographyText></div>
                </template>
              </TableColumn>
              <TableColumn :title="t('admin.dataGovernance.columns.resourceType')" :width="190">
                <template #cell="{ record }">{{ resourceTypeLabel(record.targetType) }}</template>
              </TableColumn>
              <TableColumn :title="t('admin.dataGovernance.columns.status')" :width="120">
                <template #cell="{ record }">
                  <Tag :color="record.effective ? 'red' : 'gray'">
                    {{ t(`admin.dataGovernance.holdStatuses.${record.effective ? 'effective' : record.status}`) }}
                  </Tag>
                </template>
              </TableColumn>
              <TableColumn :title="t('admin.dataGovernance.columns.reason')" data-index="reason" :width="300" />
              <TableColumn :title="t('admin.dataGovernance.columns.expiresAt')" :width="190">
                <template #cell="{ record }">{{ formatDate(record.expiresAt) }}</template>
              </TableColumn>
              <TableColumn :title="t('admin.dataGovernance.columns.actions')" fixed="right" :width="120">
                <template #cell="{ record }">
                  <Button
                    v-if="permissions.manageHolds && record.effective"
                    size="small"
                    @click="releaseHoldTarget = record"
                  >
                    {{ t('admin.dataGovernance.actions.releaseHold') }}
                  </Button>
                </template>
              </TableColumn>
            </Table>
        </TabPane>

        <TabPane key="policies" :title="t('admin.dataGovernance.tabs.policies')">
            <Table
              :data="policies"
              row-key="id"
              :pagination="false"
              :bordered="false"
              :scroll="{ x: 1240 }"
            >
              <TableColumn :title="t('admin.dataGovernance.columns.resourceType')" :width="240">
                <template #cell="{ record }">
                  <strong>{{ record.resourceLabel }}</strong>
                  <div><TypographyText type="secondary">{{ record.resourceType }}</TypographyText></div>
                </template>
              </TableColumn>
              <TableColumn :title="t('admin.dataGovernance.columns.retention')" :width="150">
                <template #cell="{ record }">
                  {{ record.retentionDays === null
                    ? t('admin.dataGovernance.indefinite')
                    : t('admin.dataGovernance.days', { count: record.retentionDays }) }}
                </template>
              </TableColumn>
              <TableColumn :title="t('admin.dataGovernance.columns.capabilities')" :width="330">
                <template #cell="{ record }">
                  <Space wrap>
                    <Tag :color="record.userDeletable ? 'blue' : 'gray'">
                      {{ t('admin.dataGovernance.capabilities.softDelete') }}
                    </Tag>
                    <Tag :color="record.moderatorRestorable ? 'green' : 'gray'">
                      {{ t('admin.dataGovernance.capabilities.restore') }}
                    </Tag>
                    <Tag :color="record.legalHoldSupported ? 'orange' : 'gray'">
                      {{ t('admin.dataGovernance.capabilities.hold') }}
                    </Tag>
                  </Space>
                </template>
              </TableColumn>
              <TableColumn :title="t('admin.dataGovernance.metrics.activeHolds')" data-index="activeHolds" :width="130" />
              <TableColumn :title="t('admin.dataGovernance.metrics.awaitingPurge')" data-index="awaitingPurge" :width="150" />
              <TableColumn :title="t('admin.dataGovernance.columns.actions')" fixed="right" :width="100">
                <template #cell="{ record }">
                  <Button v-if="permissions.managePolicies" size="small" @click="openPolicy(record)">
                    {{ t('common.edit') }}
                  </Button>
                </template>
              </TableColumn>
            </Table>
        </TabPane>
      </Tabs>
    </Card>
  </Space>

  <Drawer
    v-model:visible="policyDrawerVisible"
    :title="t('admin.dataGovernance.policyDrawerTitle')"
    :width="520"
    :footer="false"
    unmount-on-close
  >
    <Form :model="policyForm" layout="vertical" @submit="savePolicy">
      <FormItem :label="t('admin.dataGovernance.columns.resourceType')">
        <Input :model-value="selectedPolicy?.resourceLabel" disabled />
      </FormItem>
      <FormItem field="retentionDays" :label="t('admin.dataGovernance.fields.retentionDays')">
        <InputNumber v-model="policyForm.retentionDays" :min="0" :precision="0" allow-clear />
      </FormItem>
      <Grid :cols="1" :row-gap="8">
        <GridItem>
          <Space>
            <Switch v-model="policyForm.userDeletable" />
            {{ t('admin.dataGovernance.fields.userDeletable') }}
          </Space>
        </GridItem>
        <GridItem>
          <Space>
            <Switch v-model="policyForm.moderatorRestorable" />
            {{ t('admin.dataGovernance.fields.moderatorRestorable') }}
          </Space>
        </GridItem>
        <GridItem>
          <Space>
            <Switch v-model="policyForm.legalHoldSupported" />
            {{ t('admin.dataGovernance.fields.legalHoldSupported') }}
          </Space>
        </GridItem>
      </Grid>
      <FormItem field="notes" :label="t('admin.dataGovernance.fields.notes')">
        <Textarea v-model="policyForm.notes" :max-length="2000" show-word-limit />
      </FormItem>
      <FormItem field="reason" :label="t('admin.dataGovernance.fields.changeReason')" required>
        <Textarea v-model="policyForm.reason" :max-length="2000" show-word-limit />
      </FormItem>
      <Button
        type="primary"
        html-type="submit"
        long
        :loading="policySubmitting"
        :disabled="!policyForm.reason.trim()"
      >
        {{ t('common.save') }}
      </Button>
    </Form>
  </Drawer>

  <Drawer
    v-model:visible="recordDrawerVisible"
    :title="t('admin.dataGovernance.recordDrawerTitle')"
    :width="560"
    :footer="false"
    unmount-on-close
  >
    <Descriptions v-if="selectedRecord" :column="1" bordered>
      <DescriptionsItem :label="t('admin.dataGovernance.columns.content')">
        {{ selectedRecord.targetLabel }}
      </DescriptionsItem>
      <DescriptionsItem :label="t('admin.dataGovernance.columns.resourceType')">
        {{ resourceTypeLabel(selectedRecord.targetType) }}
      </DescriptionsItem>
      <DescriptionsItem :label="t('admin.dataGovernance.columns.status')">
        {{ t(`admin.dataGovernance.statuses.${selectedRecord.status}`) }}
      </DescriptionsItem>
      <DescriptionsItem :label="t('admin.dataGovernance.columns.softDeletedAt')">
        {{ formatDate(selectedRecord.softDeletedAt) }}
      </DescriptionsItem>
      <DescriptionsItem :label="t('admin.dataGovernance.columns.purgeAfter')">
        {{ formatDate(selectedRecord.purgeAfter) }}
      </DescriptionsItem>
      <DescriptionsItem :label="t('admin.dataGovernance.columns.reason')">
        {{ selectedRecord.deletionReason }}
      </DescriptionsItem>
      <DescriptionsItem :label="t('admin.dataGovernance.columns.purgeAttempts')">
        {{ selectedRecord.purgeAttempts }}
      </DescriptionsItem>
    </Descriptions>
  </Drawer>

  <Modal
    v-model:visible="createHoldVisible"
    :title="t('admin.dataGovernance.holdModalTitle')"
    :ok-text="t('admin.dataGovernance.actions.placeHold')"
    :cancel-text="t('common.cancel')"
    :ok-loading="actionSubmitting"
    :ok-button-props="{ disabled: !targetForm.targetType || !targetForm.targetReference || !targetForm.reason.trim() }"
    unmount-on-close
    @ok="createHold"
  >
    <Form :model="targetForm" layout="vertical">
      <FormItem field="targetType" :label="t('admin.dataGovernance.fields.resourceType')" required>
        <Select v-model="targetForm.targetType">
          <Option v-for="entry in resourceTypes" :key="entry.value" :value="entry.value">
            {{ entry.label }}
          </Option>
        </Select>
      </FormItem>
      <FormItem field="targetReference" :label="t('admin.dataGovernance.fields.targetReference')" required>
        <Input v-model="targetForm.targetReference" />
      </FormItem>
      <FormItem field="policyReference" :label="t('admin.dataGovernance.fields.policyReference')">
        <Input v-model="targetForm.policyReference" />
      </FormItem>
      <FormItem field="expiresAt" :label="t('admin.dataGovernance.fields.expiresAt')">
        <DatePicker
          v-model="targetForm.expiresAt"
          show-time
          value-format="YYYY-MM-DD HH:mm:ss"
        />
      </FormItem>
      <FormItem field="reason" :label="t('admin.dataGovernance.fields.holdReason')" required>
        <Textarea v-model="targetForm.reason" :max-length="2000" show-word-limit />
      </FormItem>
    </Form>
  </Modal>

  <Modal
    v-model:visible="softDeleteVisible"
    :title="t('admin.dataGovernance.softDeleteModalTitle')"
    :ok-text="t('admin.dataGovernance.actions.softDelete')"
    :cancel-text="t('common.cancel')"
    :ok-loading="actionSubmitting"
    :ok-button-props="{ disabled: !targetForm.targetType || !targetForm.targetReference || !targetForm.reason.trim() }"
    unmount-on-close
    @ok="softDelete"
  >
    <Space direction="vertical" :size="16" fill>
      <Alert type="warning" show-icon :closable="false">
        {{ t('admin.dataGovernance.softDeleteDescription') }}
      </Alert>
      <Form :model="targetForm" layout="vertical">
        <FormItem field="targetType" :label="t('admin.dataGovernance.fields.resourceType')" required>
          <Select v-model="targetForm.targetType">
            <Option v-for="entry in resourceTypes" :key="entry.value" :value="entry.value">
              {{ entry.label }}
            </Option>
          </Select>
        </FormItem>
        <FormItem field="targetReference" :label="t('admin.dataGovernance.fields.targetReference')" required>
          <Input v-model="targetForm.targetReference" />
        </FormItem>
        <FormItem field="reason" :label="t('admin.dataGovernance.fields.deletionReason')" required>
          <Textarea v-model="targetForm.reason" :max-length="2000" show-word-limit />
        </FormItem>
      </Form>
    </Space>
  </Modal>

  <Modal
    v-model:visible="releaseHoldVisible"
    :title="t('admin.dataGovernance.releaseHoldModalTitle')"
    :ok-text="t('admin.dataGovernance.actions.releaseHold')"
    :cancel-text="t('common.cancel')"
    :ok-loading="actionSubmitting"
    :ok-button-props="{ disabled: !actionReason.trim() }"
    unmount-on-close
    @ok="releaseHold"
  >
    <Form layout="vertical">
      <FormItem :label="t('admin.dataGovernance.fields.releaseReason')" required>
        <Textarea v-model="actionReason" :max-length="2000" show-word-limit />
      </FormItem>
    </Form>
  </Modal>

  <Modal
    v-model:visible="lifecycleActionVisible"
    :title="t(`admin.dataGovernance.${lifecycleAction?.action === 'purge' ? 'purgeModalTitle' : 'restoreModalTitle'}`)"
    :ok-text="t(`admin.dataGovernance.actions.${lifecycleAction?.action || 'restore'}`)"
    :cancel-text="t('common.cancel')"
    :ok-loading="actionSubmitting"
    :ok-button-props="{
      disabled: !actionReason.trim(),
      status: lifecycleAction?.action === 'purge' ? 'danger' : 'normal',
    }"
    unmount-on-close
    @ok="executeLifecycleAction"
  >
    <Space direction="vertical" :size="16" fill>
      <Alert
        :type="lifecycleAction?.action === 'purge' ? 'error' : 'info'"
        show-icon
        :closable="false"
      >
        {{ t(`admin.dataGovernance.${lifecycleAction?.action === 'purge' ? 'purgeDescription' : 'restoreDescription'}`) }}
      </Alert>
      <Form layout="vertical">
        <FormItem :label="t('admin.dataGovernance.fields.actionReason')" required>
          <Textarea v-model="actionReason" :max-length="2000" show-word-limit />
        </FormItem>
      </Form>
    </Space>
  </Modal>
</template>
