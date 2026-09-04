<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import { Message, Modal } from '@mcweb/ui'
import { createIdempotencyKey } from '@/lib/idempotency'
import { HttpError, postJson } from '@/lib/http'
import type {
  WorldRestorePlanRow,
  WorldRestoreResolutionRow,
  WorldSafetyProps,
} from './worldRestoreTypes'

interface PlanResponse {
  plan: WorldRestorePlanRow
  confirmation: string
  idempotent: boolean
}

interface AuthorizationResponse {
  authorization_token: string
  authorization_method: string
  confirmation: string
  request_id: string
  expires_in: number
  plan: WorldRestorePlanRow
}

interface PlanLifecycleResponse {
  message?: string
  plan: WorldRestorePlanRow
  idempotent: boolean
}

interface RecoveryPlanResponse {
  plan: WorldRestorePlanRow
  resolution: WorldRestoreResolutionRow
  confirmation: string
  idempotent: boolean
}

interface RecoveryAuthorizationResponse {
  authorization_token: string
  authorization_method: string
  confirmation: string
  request_id: string
  expires_in: number
  plan: WorldRestorePlanRow
  resolution: WorldRestoreResolutionRow
}

interface RecoveryLifecycleResponse {
  message?: string
  plan: WorldRestorePlanRow
  resolution: WorldRestoreResolutionRow
  replacement?: WorldRestoreResolutionRow
  confirmation?: string
  idempotent: boolean
}

const props = defineProps<{ model: WorldSafetyProps }>()
const { t, locale } = useI18n()

const selectedBackupId = ref('')
const reason = ref('')
const requestId = ref(createIdempotencyKey())
const plan = ref<WorldRestorePlanRow | null>(initialOwnedPlan())
const password = ref('')
const verificationCode = ref('')
const authorizationToken = ref('')
const requiredConfirmation = ref('')
const confirmation = ref('')
const authorizationExpiresIn = ref(0)
const cancelReason = ref('')
const cancelRequestId = ref(createIdempotencyKey())
const planning = ref(false)
const authorizing = ref(false)
const executing = ref(false)
const cancelling = ref(false)
const creatingBackup = ref(false)
const executionQueued = ref(false)
const errorMessage = ref('')
const recoveryPlan = computed(() => props.model.plans.find((candidate) => (
  candidate.status === 'recovery_required' && Boolean(candidate.plan_recovery_url)
)) || null)
const recoveryResolution = ref<WorldRestoreResolutionRow | null>(
  recoveryPlan.value?.recovery_resolution || null,
)
const recoveryAction = ref<'resume' | 'rollback' | 'reconcile'>('reconcile')
const recoveryReason = ref('')
const recoveryRequestId = ref(createIdempotencyKey())
const recoveryPassword = ref('')
const recoveryCode = ref('')
const recoveryAuthorizationToken = ref('')
const recoveryRequiredConfirmation = ref('')
const recoveryConfirmation = ref('')
const recoveryPlanning = ref(false)
const recoveryAuthorizing = ref(false)
const recoveryExecuting = ref(false)
const recoveryQueued = ref(false)
const lifecycleReason = ref('')
const lifecyclePassword = ref('')
const lifecycleCode = ref('')
const lifecycleCancelRequestId = ref(createIdempotencyKey())
const lifecycleTakeoverRequestId = ref(createIdempotencyKey())
const lifecycleManaging = ref<'cancel' | 'takeover' | ''>('')

const availableBackups = computed(() => props.model.backups.filter((backup) => (
  backup.restorable && backup.target_compatible
)))
const allBlockers = computed(() => Array.from(new Set([
  ...(props.model.can_create_backup ? props.model.backup_blockers : []),
  ...(props.model.can_restore ? props.model.restore_blockers : []),
])))
const currentStep = computed(() => {
  if (authorizationToken.value) return 3
  if (plan.value) return 2
  return 1
})
const canPlan = computed(() => (
  Boolean(props.model.create_restore_url)
  && props.model.restore_blockers.length === 0
  && availableBackups.value.some((backup) => backup.id === selectedBackupId.value)
  && reason.value.trim().length > 0
  && reason.value.trim().length <= 1000
  && !planning.value
))
const canAuthorize = computed(() => (
  Boolean(plan.value?.authorize_url)
  && Boolean(plan.value?.resumable)
  && password.value.length > 0
  && !authorizing.value
))
const canExecute = computed(() => (
  Boolean(plan.value?.execute_url)
  && Boolean(plan.value?.resumable)
  && authorizationToken.value.length > 0
  && confirmation.value === requiredConfirmation.value
  && !executing.value
  && !executionQueued.value
))
const canCancelPlan = computed(() => (
  Boolean(plan.value?.cancel_url)
  && Boolean(plan.value?.resumable)
  && cancelReason.value.trim().length > 0
  && cancelReason.value.trim().length <= 1000
  && !planning.value
  && !authorizing.value
  && !executing.value
  && !cancelling.value
  && !executionQueued.value
))
const canPlanRecovery = computed(() => (
  Boolean(recoveryPlan.value?.plan_recovery_url)
  && props.model.recovery_blockers.length === 0
  && recoveryReason.value.trim().length > 0
  && recoveryReason.value.trim().length <= 1000
  && !recoveryPlanning.value
))
const canAuthorizeRecovery = computed(() => (
  Boolean(recoveryResolution.value?.authorize_url)
  && Boolean(recoveryResolution.value?.resumable)
  && recoveryPassword.value.length > 0
  && !recoveryAuthorizing.value
))
const canExecuteRecovery = computed(() => (
  Boolean(recoveryResolution.value?.execute_url)
  && Boolean(recoveryResolution.value?.resumable)
  && recoveryAuthorizationToken.value.length > 0
  && recoveryConfirmation.value === recoveryRequiredConfirmation.value
  && !recoveryExecuting.value
  && !recoveryQueued.value
))
const lifecycleInputValid = computed(() => (
  lifecycleReason.value.trim().length > 0
  && lifecycleReason.value.trim().length <= 1000
  && lifecyclePassword.value.length > 0
  && lifecycleManaging.value === ''
))
const canCancelRecovery = computed(() => (
  Boolean(recoveryResolution.value?.cancel_url)
  && lifecycleInputValid.value
))
const canTakeoverRecovery = computed(() => (
  Boolean(recoveryResolution.value?.takeover_url)
  && props.model.recovery_blockers.length === 0
  && lifecycleInputValid.value
))

watch([selectedBackupId, reason], () => {
  if (!plan.value) requestId.value = createIdempotencyKey()
})

watch(cancelReason, () => {
  if (!cancelling.value) cancelRequestId.value = createIdempotencyKey()
})

watch(() => props.model.plans, () => {
  if (!authorizationToken.value && !executionQueued.value) plan.value = initialOwnedPlan()
}, { deep: true })

watch(() => recoveryPlan.value?.recovery_resolution, (value) => {
  if (!recoveryAuthorizationToken.value) recoveryResolution.value = value || null
})

watch([recoveryAction, recoveryReason], () => {
  if (!recoveryResolution.value || ['failed', 'recovery_required', 'expired', 'cancelled', 'taken_over'].includes(recoveryResolution.value.status)) {
    recoveryRequestId.value = createIdempotencyKey()
  }
})

watch([lifecycleReason, lifecyclePassword, lifecycleCode, recoveryAction], () => {
  if (!lifecycleManaging.value) {
    lifecycleCancelRequestId.value = createIdempotencyKey()
    lifecycleTakeoverRequestId.value = createIdempotencyKey()
  }
})

function initialOwnedPlan() {
  return props.model.plans.find((candidate) => candidate.resumable) || null
}

function translateStatus(status: string) {
  return t(`adminMinecraft.worldSafety.statuses.${status}`)
}

function translatePurpose(purpose: string) {
  return t(`adminMinecraft.worldSafety.purposes.${purpose}`)
}

function translatePhase(phase: string) {
  return t(`adminMinecraft.worldSafety.phases.${phase}`)
}

function translateBlocker(blocker: string) {
  return t(`adminMinecraft.worldSafety.blockers.${blocker}`)
}

function translateRecoveryAction(action: string) {
  return t(`adminMinecraft.worldSafety.recoveryActions.${action}`)
}

function formatBytes(value?: number) {
  if (value === undefined || value === null) return '—'
  if (value === 0) return '0 B'
  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB']
  const index = Math.min(Math.floor(Math.log(value) / Math.log(1024)), units.length - 1)
  return `${(value / (1024 ** index)).toFixed(index === 0 ? 0 : 2)} ${units[index]}`
}

function formatDate(value?: string) {
  if (!value) return '—'
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return '—'
  return new Intl.DateTimeFormat(locale.value, { dateStyle: 'medium', timeStyle: 'medium' }).format(date)
}

function errorText(error: unknown) {
  if (error instanceof HttpError && error.body && typeof error.body === 'object') {
    const message = (error.body as { error?: unknown }).error
    if (typeof message === 'string' && message.length > 0) return message
  }
  return t('adminMinecraft.worldSafety.requestFailed')
}

const stateConflictCodes = new Set([
  'world_restore_active',
  'world_restore_authorization_expired',
  'world_restore_authorization_invalid',
  'world_restore_idempotency_conflict',
  'world_restore_plan_expired',
  'world_restore_plan_not_authorizable',
  'world_restore_plan_not_authorized',
  'world_restore_plan_not_cancellable',
  'world_restore_recovery_active',
  'world_restore_recovery_authorization_expired',
  'world_restore_recovery_authorization_invalid',
  'world_restore_recovery_idempotency_conflict',
  'world_restore_recovery_lifecycle_not_allowed',
  'world_restore_recovery_not_authorizable',
  'world_restore_recovery_not_authorized',
  'world_restore_recovery_resolution_expired',
  'world_restore_recovery_stale',
  'world_restore_stale',
])

function stateConflict(error: unknown) {
  if (!(error instanceof HttpError)) return false
  const code = error.body && typeof error.body === 'object'
    ? (error.body as { code?: unknown }).code
    : undefined
  return error.status === 409 || (
    typeof code === 'string'
    && (stateConflictCodes.has(code) || code.includes('_changed'))
  )
}

function clearPlanAuthorization() {
  password.value = ''
  verificationCode.value = ''
  authorizationToken.value = ''
  requiredConfirmation.value = ''
  confirmation.value = ''
  authorizationExpiresIn.value = 0
  executionQueued.value = false
}

function clearPlanSelection() {
  plan.value = null
  selectedBackupId.value = ''
  reason.value = ''
  requestId.value = createIdempotencyKey()
  cancelReason.value = ''
  cancelRequestId.value = createIdempotencyKey()
  clearPlanAuthorization()
}

function clearRecoverySelection() {
  recoveryResolution.value = null
  recoveryAction.value = 'reconcile'
  recoveryReason.value = ''
  recoveryRequestId.value = createIdempotencyKey()
  recoveryPassword.value = ''
  recoveryCode.value = ''
  recoveryAuthorizationToken.value = ''
  recoveryRequiredConfirmation.value = ''
  recoveryConfirmation.value = ''
  recoveryQueued.value = false
  lifecycleReason.value = ''
  lifecyclePassword.value = ''
  lifecycleCode.value = ''
  lifecycleCancelRequestId.value = createIdempotencyKey()
  lifecycleTakeoverRequestId.value = createIdempotencyKey()
}

function handleRequestError(error: unknown, scope: 'plan' | 'recovery') {
  errorMessage.value = errorText(error)
  if (!stateConflict(error)) return

  if (scope === 'plan') clearPlanSelection()
  else clearRecoverySelection()
  refresh()
}

function refresh() {
  router.reload({ only: ['worldSafety'], preserveScroll: true })
}

function continuePlan(candidate: WorldRestorePlanRow) {
  if (!candidate.resumable) return
  clearPlanAuthorization()
  plan.value = candidate
  selectedBackupId.value = candidate.backup_id
  reason.value = candidate.reason
  cancelReason.value = ''
  cancelRequestId.value = createIdempotencyKey()
  errorMessage.value = ''
}

function confirmBackup() {
  if (!props.model.create_backup_url || props.model.backup_blockers.length > 0) return
  Modal.warning({
    title: t('adminMinecraft.worldSafety.createBackup'),
    content: t('adminMinecraft.worldSafety.createBackupConfirm'),
    okText: t('adminMinecraft.worldSafety.createBackup'),
    cancelText: t('common.cancel'),
    hideCancel: false,
    onOk: requestBackup,
  })
}

async function requestBackup() {
  if (!props.model.create_backup_url || creatingBackup.value) return
  creatingBackup.value = true
  errorMessage.value = ''
  try {
    const result = await postJson<{ message?: string }>(props.model.create_backup_url, {
      request_id: createIdempotencyKey(),
    })
    Message.success(result.message || t('adminMinecraft.worldSafety.backupQueued'))
    refresh()
  } catch (error) {
    errorMessage.value = errorText(error)
  } finally {
    creatingBackup.value = false
  }
}

async function createPlan() {
  if (!canPlan.value || !props.model.create_restore_url) return
  planning.value = true
  errorMessage.value = ''
  try {
    const result = await postJson<PlanResponse>(props.model.create_restore_url, {
      backup_id: selectedBackupId.value,
      reason: reason.value.trim(),
      request_id: requestId.value,
    })
    plan.value = result.plan
    clearPlanAuthorization()
    cancelReason.value = ''
    cancelRequestId.value = createIdempotencyKey()
  } catch (error) {
    handleRequestError(error, 'plan')
  } finally {
    planning.value = false
  }
}

async function authorizePlan() {
  if (!canAuthorize.value || !plan.value?.authorize_url) return
  authorizing.value = true
  errorMessage.value = ''
  try {
    const result = await postJson<AuthorizationResponse>(plan.value.authorize_url, {
      password: password.value,
      code: verificationCode.value,
    })
    plan.value = result.plan
    authorizationToken.value = result.authorization_token
    requiredConfirmation.value = result.confirmation
    authorizationExpiresIn.value = result.expires_in
    password.value = ''
    verificationCode.value = ''
    confirmation.value = ''
  } catch (error) {
    handleRequestError(error, 'plan')
  } finally {
    authorizing.value = false
  }
}

async function executeRestore() {
  if (!canExecute.value || !plan.value?.execute_url) return
  executing.value = true
  errorMessage.value = ''
  try {
    const result = await postJson<{ message?: string; plan: WorldRestorePlanRow }>(
      plan.value.execute_url,
      {
        authorization_token: authorizationToken.value,
        confirmation: confirmation.value,
      },
    )
    plan.value = result.plan
    executionQueued.value = true
    authorizationToken.value = ''
    password.value = ''
    verificationCode.value = ''
    Message.success(result.message || t('adminMinecraft.worldSafety.restoreQueued'))
    refresh()
  } catch (error) {
    handleRequestError(error, 'plan')
  } finally {
    executing.value = false
  }
}

function confirmPlanCancellation() {
  if (!canCancelPlan.value || !plan.value?.cancel_url) return
  Modal.warning({
    title: t('adminMinecraft.worldSafety.cancelPlan'),
    content: t('adminMinecraft.worldSafety.cancelPlanConfirm'),
    okText: t('adminMinecraft.worldSafety.cancelPlan'),
    cancelText: t('common.cancel'),
    hideCancel: false,
    onOk: cancelPlan,
  })
}

async function cancelPlan() {
  if (!canCancelPlan.value || !plan.value?.cancel_url) return
  cancelling.value = true
  errorMessage.value = ''
  try {
    const result = await postJson<PlanLifecycleResponse>(plan.value.cancel_url, {
      reason: cancelReason.value.trim(),
      request_id: cancelRequestId.value,
      expected_lock_version: plan.value.lock_version,
    })
    Message.success(result.message || t('adminMinecraft.worldSafety.planCancelled'))
    clearPlanSelection()
    refresh()
  } catch (error) {
    handleRequestError(error, 'plan')
  } finally {
    cancelling.value = false
  }
}

async function planRecoveryResolution() {
  if (!canPlanRecovery.value || !recoveryPlan.value?.plan_recovery_url) return
  recoveryPlanning.value = true
  errorMessage.value = ''
  try {
    const result = await postJson<RecoveryPlanResponse>(recoveryPlan.value.plan_recovery_url, {
      resolution_action: recoveryAction.value,
      reason: recoveryReason.value.trim(),
      request_id: recoveryRequestId.value,
      expected_plan_lock_version: recoveryPlan.value.lock_version,
    })
    recoveryResolution.value = result.resolution
    recoveryRequiredConfirmation.value = result.confirmation
    recoveryPassword.value = ''
    recoveryCode.value = ''
  } catch (error) {
    handleRequestError(error, 'recovery')
  } finally {
    recoveryPlanning.value = false
  }
}

async function authorizeRecoveryResolution() {
  if (!canAuthorizeRecovery.value || !recoveryResolution.value?.authorize_url) return
  recoveryAuthorizing.value = true
  errorMessage.value = ''
  try {
    const result = await postJson<RecoveryAuthorizationResponse>(
      recoveryResolution.value.authorize_url,
      {
        resolution_id: recoveryResolution.value.id,
        password: recoveryPassword.value,
        code: recoveryCode.value,
        expected_lock_version: recoveryResolution.value.lock_version,
      },
    )
    recoveryResolution.value = result.resolution
    recoveryAuthorizationToken.value = result.authorization_token
    recoveryRequiredConfirmation.value = result.confirmation
    recoveryConfirmation.value = ''
    recoveryPassword.value = ''
    recoveryCode.value = ''
  } catch (error) {
    handleRequestError(error, 'recovery')
  } finally {
    recoveryAuthorizing.value = false
  }
}

async function executeRecoveryResolution() {
  if (!canExecuteRecovery.value || !recoveryResolution.value?.execute_url) return
  recoveryExecuting.value = true
  errorMessage.value = ''
  try {
    const result = await postJson<{
      message?: string
      plan: WorldRestorePlanRow
      resolution: WorldRestoreResolutionRow
    }>(recoveryResolution.value.execute_url, {
      resolution_id: recoveryResolution.value.id,
      authorization_token: recoveryAuthorizationToken.value,
      confirmation: recoveryConfirmation.value,
      expected_lock_version: recoveryResolution.value.lock_version,
    })
    recoveryResolution.value = result.resolution
    recoveryQueued.value = true
    recoveryAuthorizationToken.value = ''
    recoveryPassword.value = ''
    recoveryCode.value = ''
    Message.success(result.message || t('adminMinecraft.worldSafety.recoveryQueued'))
    refresh()
  } catch (error) {
    handleRequestError(error, 'recovery')
  } finally {
    recoveryExecuting.value = false
  }
}

async function manageRecoveryLifecycle(action: 'cancel' | 'takeover') {
  if (!recoveryResolution.value || !recoveryPlan.value) return
  const url = action === 'cancel'
    ? recoveryResolution.value.cancel_url
    : recoveryResolution.value.takeover_url
  if (!url || (action === 'cancel' ? !canCancelRecovery.value : !canTakeoverRecovery.value)) return

  lifecycleManaging.value = action
  errorMessage.value = ''
  try {
    const result = await postJson<RecoveryLifecycleResponse>(url, {
      resolution_id: recoveryResolution.value.id,
      resolution_action: action === 'takeover' ? recoveryAction.value : undefined,
      reason: lifecycleReason.value.trim(),
      request_id: action === 'cancel'
        ? lifecycleCancelRequestId.value
        : lifecycleTakeoverRequestId.value,
      expected_plan_lock_version: recoveryPlan.value.lock_version,
      expected_resolution_lock_version: recoveryResolution.value.lock_version,
      password: lifecyclePassword.value,
      code: lifecycleCode.value,
    })
    recoveryResolution.value = result.replacement || result.resolution
    recoveryRequiredConfirmation.value = result.confirmation || ''
    recoveryAuthorizationToken.value = ''
    recoveryConfirmation.value = ''
    lifecyclePassword.value = ''
    lifecycleCode.value = ''
    lifecycleReason.value = ''
    Message.success(result.message || t(`adminMinecraft.worldSafety.recoveryLifecycle${action === 'cancel' ? 'Cancelled' : 'TakenOver'}`))
    refresh()
  } catch (error) {
    handleRequestError(error, 'recovery')
  } finally {
    lifecycleManaging.value = ''
  }
}
</script>

<template>
  <a-card
    v-if="model.visible"
    :title="t('adminMinecraft.worldSafety.title')"
    :bordered="true"
    class="mt-4"
  >
    <template #extra>
      <a-button size="small" @click="refresh">
        {{ t('adminMinecraft.worldSafety.refresh') }}
      </a-button>
    </template>

    <a-space direction="vertical" fill :size="16">
      <a-alert v-if="errorMessage" type="error" show-icon :closable="false">
        {{ errorMessage }}
      </a-alert>

      <a-alert type="warning" show-icon :closable="false">
        <template #title>{{ t('adminMinecraft.worldSafety.stoppedWarningTitle') }}</template>
        {{ t('adminMinecraft.worldSafety.stoppedWarningBody') }}
      </a-alert>

      <a-alert
        v-for="blocker in allBlockers"
        :key="blocker"
        :type="blocker === 'recovery_required' ? 'error' : 'warning'"
        show-icon
        :closable="false"
      >
        {{ translateBlocker(blocker) }}
      </a-alert>

      <a-space v-if="model.can_create_backup" wrap>
        <a-button
          type="primary"
          :loading="creatingBackup"
          :disabled="model.backup_blockers.length > 0"
          @click="confirmBackup"
        >
          {{ t('adminMinecraft.worldSafety.createBackup') }}
        </a-button>
      </a-space>

      <a-table
        :data="model.backups"
        :pagination="false"
        row-key="id"
        :scroll="{ x: 980 }"
      >
        <template #columns>
          <a-table-column :title="t('adminMinecraft.worldSafety.backupId')" data-index="id">
            <template #cell="{ record }"><a-typography-text code>{{ record.id }}</a-typography-text></template>
          </a-table-column>
          <a-table-column :title="t('adminMinecraft.worldSafety.purpose')" data-index="purpose">
            <template #cell="{ record }">{{ translatePurpose(record.purpose) }}</template>
          </a-table-column>
          <a-table-column :title="t('adminMinecraft.worldSafety.status')" data-index="status">
            <template #cell="{ record }">
              <a-tag :color="record.status === 'available' ? 'green' : record.status === 'failed' ? 'red' : 'blue'">
                {{ translateStatus(record.status) }}
              </a-tag>
            </template>
          </a-table-column>
          <a-table-column :title="t('adminMinecraft.worldSafety.createdAt')" data-index="created_at">
            <template #cell="{ record }">{{ formatDate(record.created_at) }}</template>
          </a-table-column>
          <a-table-column :title="t('adminMinecraft.worldSafety.archiveSize')" data-index="archive_bytes">
            <template #cell="{ record }">{{ formatBytes(record.archive_bytes) }}</template>
          </a-table-column>
          <a-table-column :title="t('adminMinecraft.worldSafety.uncompressedSize')" data-index="uncompressed_bytes">
            <template #cell="{ record }">{{ formatBytes(record.uncompressed_bytes) }}</template>
          </a-table-column>
          <a-table-column :title="t('adminMinecraft.worldSafety.entryCount')" data-index="entry_count" />
          <a-table-column :title="t('adminMinecraft.worldSafety.manifestDigest')" data-index="manifest_digest_short">
            <template #cell="{ record }"><a-typography-text code>{{ record.manifest_digest_short || '—' }}</a-typography-text></template>
          </a-table-column>
          <a-table-column :title="t('adminMinecraft.worldSafety.error')" data-index="error_code">
            <template #cell="{ record }">{{ record.error_code || '—' }}</template>
          </a-table-column>
        </template>
        <template #empty>{{ t('adminMinecraft.worldSafety.noBackups') }}</template>
      </a-table>

      <template v-if="model.can_restore || model.can_resolve_recovery">
        <template v-if="model.can_restore">
          <a-divider />
          <a-alert v-if="plan?.resumable" type="info" show-icon :closable="false">
            <template #title>{{ t('adminMinecraft.worldSafety.continuePlanTitle') }}</template>
            {{ t('adminMinecraft.worldSafety.continuePlanBody', { id: plan.id }) }}
          </a-alert>
          <a-steps :current="currentStep" size="small">
          <a-step :title="t('adminMinecraft.worldSafety.stepPlan')" />
          <a-step :title="t('adminMinecraft.worldSafety.stepAuthorize')" />
          <a-step :title="t('adminMinecraft.worldSafety.stepExecute')" />
          </a-steps>

          <a-form layout="vertical" class="world-restore-form">
          <template v-if="!plan">
            <a-form-item field="backup" :label="t('adminMinecraft.worldSafety.selectBackup')" required>
              <a-select v-model="selectedBackupId" :disabled="model.restore_blockers.length > 0">
                <a-option v-for="backup in availableBackups" :key="backup.id" :value="backup.id">
                  {{ backup.id }} · {{ formatDate(backup.verified_at) }}
                </a-option>
              </a-select>
            </a-form-item>
            <a-form-item field="reason" :label="t('adminMinecraft.worldSafety.reason')" required>
              <a-textarea
                v-model="reason"
                :max-length="1000"
                show-word-limit
                :auto-size="{ minRows: 3, maxRows: 6 }"
                :placeholder="t('adminMinecraft.worldSafety.reasonPlaceholder')"
                :disabled="model.restore_blockers.length > 0"
              />
            </a-form-item>
            <a-button type="primary" status="warning" :loading="planning" :disabled="!canPlan" @click="createPlan">
              {{ t('adminMinecraft.worldSafety.freezePlan') }}
            </a-button>
          </template>

          <template v-else-if="plan.resumable && !authorizationToken && !executionQueued">
            <a-descriptions :column="1" bordered size="small">
              <a-descriptions-item :label="t('adminMinecraft.worldSafety.planId')">
                <a-typography-text code>{{ plan.id }}</a-typography-text>
              </a-descriptions-item>
              <a-descriptions-item :label="t('adminMinecraft.worldSafety.backupId')">
                <a-typography-text code>{{ plan.backup_id }}</a-typography-text>
              </a-descriptions-item>
              <a-descriptions-item :label="t('adminMinecraft.worldSafety.reason')">{{ plan.reason }}</a-descriptions-item>
              <a-descriptions-item :label="t('adminMinecraft.worldSafety.expiresAt')">{{ formatDate(plan.expires_at) }}</a-descriptions-item>
            </a-descriptions>
            <a-form-item field="password" :label="t('adminMinecraft.worldSafety.password')" required>
              <a-input-password v-model="password" autocomplete="current-password" :disabled="authorizing" />
            </a-form-item>
            <a-form-item
              field="verificationCode"
              :label="t('adminMinecraft.worldSafety.verificationCode')"
              :extra="t('adminMinecraft.worldSafety.verificationCodeHint')"
            >
              <a-input
                v-model="verificationCode"
                autocomplete="one-time-code"
                inputmode="numeric"
                :disabled="authorizing"
              />
            </a-form-item>
            <a-button type="primary" status="warning" :loading="authorizing" :disabled="!canAuthorize" @click="authorizePlan">
              {{ t('adminMinecraft.worldSafety.authorize') }}
            </a-button>
          </template>

          <template v-else-if="plan.resumable && !executionQueued">
            <a-alert type="error" show-icon :closable="false">
              <template #title>{{ t('adminMinecraft.worldSafety.finalWarningTitle') }}</template>
              {{ t('adminMinecraft.worldSafety.finalWarningBody') }}
            </a-alert>
            <a-alert type="info" show-icon :closable="false">
              {{ t('adminMinecraft.worldSafety.authorizationExpires', { minutes: Math.max(1, Math.ceil(authorizationExpiresIn / 60)) }) }}
            </a-alert>
            <a-form-item field="confirmation" :label="t('adminMinecraft.worldSafety.confirmation')" required>
              <a-input v-model="confirmation" autocomplete="off" :disabled="executing" />
              <template #extra>
                <a-space direction="vertical" :size="8" fill>
                  <span>{{ t('adminMinecraft.worldSafety.confirmationHint') }}</span>
                  <a-typography-text code copyable>{{ requiredConfirmation }}</a-typography-text>
                </a-space>
              </template>
            </a-form-item>
            <a-button type="primary" status="danger" :loading="executing" :disabled="!canExecute" @click="executeRestore">
              {{ t('adminMinecraft.worldSafety.execute') }}
            </a-button>
          </template>

          <template v-if="plan?.resumable && !executionQueued">
            <a-divider />
            <a-alert type="warning" show-icon :closable="false">
              <template #title>{{ t('adminMinecraft.worldSafety.cancelPlanTitle') }}</template>
              {{ t('adminMinecraft.worldSafety.cancelPlanBody') }}
            </a-alert>
            <a-form-item field="cancelReason" :label="t('adminMinecraft.worldSafety.cancelPlanReason')" required>
              <a-textarea
                v-model="cancelReason"
                :max-length="1000"
                show-word-limit
                :auto-size="{ minRows: 2, maxRows: 5 }"
                :placeholder="t('adminMinecraft.worldSafety.cancelPlanReasonPlaceholder')"
                :disabled="cancelling || authorizing || executing"
              />
            </a-form-item>
            <a-button
              status="warning"
              :loading="cancelling"
              :disabled="!canCancelPlan"
              @click="confirmPlanCancellation"
            >
              {{ t('adminMinecraft.worldSafety.cancelPlan') }}
            </a-button>
          </template>
          </a-form>
        </template>

        <a-card
          v-if="model.can_resolve_recovery && recoveryPlan"
          :title="t('adminMinecraft.worldSafety.recoveryTitle')"
          :bordered="true"
          class="recovery-resolution-card"
        >
          <a-space direction="vertical" fill :size="16">
            <a-alert type="error" show-icon :closable="false">
              <template #title>{{ t('adminMinecraft.worldSafety.recoveryRiskTitle') }}</template>
              {{ t('adminMinecraft.worldSafety.recoveryRiskBody') }}
            </a-alert>
            <a-alert
              v-for="blocker in model.recovery_blockers"
              :key="`recovery-${blocker}`"
              type="error"
              show-icon
              :closable="false"
            >
              {{ translateBlocker(blocker) }}
            </a-alert>
            <a-descriptions :column="1" bordered size="small">
              <a-descriptions-item :label="t('adminMinecraft.worldSafety.planId')">
                <a-typography-text code>{{ recoveryPlan.id }}</a-typography-text>
              </a-descriptions-item>
              <a-descriptions-item :label="t('adminMinecraft.worldSafety.status')">
                {{ translateStatus(recoveryPlan.status) }}
              </a-descriptions-item>
              <a-descriptions-item
                v-if="recoveryResolution"
                :label="t('adminMinecraft.worldSafety.recoveryResolutionStatus')"
              >
                {{ translateStatus(recoveryResolution.is_expired ? 'expired' : recoveryResolution.status) }} ·
                {{ translateRecoveryAction(recoveryResolution.resolution_action) }}
              </a-descriptions-item>
              <a-descriptions-item
                v-if="recoveryResolution?.expires_at"
                :label="t('adminMinecraft.worldSafety.recoveryResolutionExpiresAt')"
              >
                {{ formatDate(recoveryResolution.expires_at) }}
              </a-descriptions-item>
              <a-descriptions-item
                v-if="recoveryResolution?.verified_world_state"
                :label="t('adminMinecraft.worldSafety.verifiedWorldState')"
              >
                {{ recoveryResolution.verified_world_state }}
              </a-descriptions-item>
            </a-descriptions>

            <a-form layout="vertical">
              <template v-if="!recoveryResolution || recoveryResolution.is_expired || ['failed', 'recovery_required', 'expired', 'cancelled', 'taken_over'].includes(recoveryResolution.status)">
                <a-form-item field="recoveryAction" :label="t('adminMinecraft.worldSafety.recoveryAction')" required>
                  <a-select v-model="recoveryAction" :disabled="recoveryPlanning">
                    <a-option value="reconcile">{{ translateRecoveryAction('reconcile') }}</a-option>
                    <a-option value="resume">{{ translateRecoveryAction('resume') }}</a-option>
                    <a-option value="rollback">{{ translateRecoveryAction('rollback') }}</a-option>
                  </a-select>
                </a-form-item>
                <a-form-item field="recoveryReason" :label="t('adminMinecraft.worldSafety.recoveryReason')" required>
                  <a-textarea
                    v-model="recoveryReason"
                    :max-length="1000"
                    show-word-limit
                    :auto-size="{ minRows: 3, maxRows: 6 }"
                    :placeholder="t('adminMinecraft.worldSafety.recoveryReasonPlaceholder')"
                    :disabled="recoveryPlanning"
                  />
                </a-form-item>
                <a-button
                  type="primary"
                  status="danger"
                  :loading="recoveryPlanning"
                  :disabled="!canPlanRecovery"
                  @click="planRecoveryResolution"
                >
                  {{ t('adminMinecraft.worldSafety.planRecovery') }}
                </a-button>
              </template>

              <template v-else-if="!recoveryAuthorizationToken && !recoveryQueued && recoveryResolution.resumable && recoveryResolution.authorize_url">
                <a-form-item field="recoveryPassword" :label="t('adminMinecraft.worldSafety.password')" required>
                  <a-input-password
                    v-model="recoveryPassword"
                    autocomplete="current-password"
                    :disabled="recoveryAuthorizing"
                  />
                </a-form-item>
                <a-form-item
                  field="recoveryCode"
                  :label="t('adminMinecraft.worldSafety.verificationCode')"
                  :extra="t('adminMinecraft.worldSafety.verificationCodeHint')"
                >
                  <a-input
                    v-model="recoveryCode"
                    autocomplete="one-time-code"
                    inputmode="numeric"
                    :disabled="recoveryAuthorizing"
                  />
                </a-form-item>
                <a-button
                  type="primary"
                  status="danger"
                  :loading="recoveryAuthorizing"
                  :disabled="!canAuthorizeRecovery"
                  @click="authorizeRecoveryResolution"
                >
                  {{ t('adminMinecraft.worldSafety.authorizeRecovery') }}
                </a-button>
              </template>

              <template v-else-if="!recoveryQueued && recoveryAuthorizationToken">
                <a-form-item field="recoveryConfirmation" :label="t('adminMinecraft.worldSafety.confirmation')" required>
                  <a-input v-model="recoveryConfirmation" autocomplete="off" :disabled="recoveryExecuting" />
                  <template #extra>
                    <a-space direction="vertical" :size="8" fill>
                      <span>{{ t('adminMinecraft.worldSafety.confirmationHint') }}</span>
                      <a-typography-text code copyable>{{ recoveryRequiredConfirmation }}</a-typography-text>
                    </a-space>
                  </template>
                </a-form-item>
                <a-button
                  type="primary"
                  status="danger"
                  :loading="recoveryExecuting"
                  :disabled="!canExecuteRecovery"
                  @click="executeRecoveryResolution"
                >
                  {{ t('adminMinecraft.worldSafety.executeRecovery') }}
                </a-button>
              </template>
            </a-form>

            <template v-if="recoveryResolution && !recoveryResolution.is_expired && ['planned', 'authorized'].includes(recoveryResolution.status)">
              <a-divider />
              <a-alert type="warning" show-icon :closable="false">
                <template #title>{{ t('adminMinecraft.worldSafety.recoveryLifecycleTitle') }}</template>
                {{ t('adminMinecraft.worldSafety.recoveryLifecycleBody') }}
              </a-alert>
              <a-form layout="vertical">
                <a-form-item field="takeoverRecoveryAction" :label="t('adminMinecraft.worldSafety.takeoverRecoveryAction')" required>
                  <a-select v-model="recoveryAction" :disabled="Boolean(lifecycleManaging)">
                    <a-option value="reconcile">{{ translateRecoveryAction('reconcile') }}</a-option>
                    <a-option value="resume">{{ translateRecoveryAction('resume') }}</a-option>
                    <a-option value="rollback">{{ translateRecoveryAction('rollback') }}</a-option>
                  </a-select>
                </a-form-item>
                <a-form-item field="lifecycleReason" :label="t('adminMinecraft.worldSafety.recoveryLifecycleReason')" required>
                  <a-textarea
                    v-model="lifecycleReason"
                    :max-length="1000"
                    show-word-limit
                    :auto-size="{ minRows: 3, maxRows: 6 }"
                    :disabled="Boolean(lifecycleManaging)"
                  />
                </a-form-item>
                <a-form-item field="lifecyclePassword" :label="t('adminMinecraft.worldSafety.password')" required>
                  <a-input-password
                    v-model="lifecyclePassword"
                    autocomplete="current-password"
                    :disabled="Boolean(lifecycleManaging)"
                  />
                </a-form-item>
                <a-form-item
                  field="lifecycleCode"
                  :label="t('adminMinecraft.worldSafety.verificationCode')"
                  :extra="t('adminMinecraft.worldSafety.verificationCodeHint')"
                >
                  <a-input
                    v-model="lifecycleCode"
                    autocomplete="one-time-code"
                    inputmode="numeric"
                    :disabled="Boolean(lifecycleManaging)"
                  />
                </a-form-item>
                <a-space wrap>
                  <a-button
                    status="warning"
                    :loading="lifecycleManaging === 'cancel'"
                    :disabled="!canCancelRecovery"
                    @click="manageRecoveryLifecycle('cancel')"
                  >
                    {{ t('adminMinecraft.worldSafety.cancelRecoveryResolution') }}
                  </a-button>
                  <a-button
                    type="primary"
                    status="danger"
                    :loading="lifecycleManaging === 'takeover'"
                    :disabled="!canTakeoverRecovery"
                    @click="manageRecoveryLifecycle('takeover')"
                  >
                    {{ t('adminMinecraft.worldSafety.takeoverRecoveryResolution') }}
                  </a-button>
                </a-space>
              </a-form>
            </template>
          </a-space>
        </a-card>

        <a-table :data="model.plans" :pagination="false" row-key="id" :scroll="{ x: 900 }">
          <template #columns>
            <a-table-column :title="t('adminMinecraft.worldSafety.planId')" data-index="id">
              <template #cell="{ record }"><a-typography-text code>{{ record.id }}</a-typography-text></template>
            </a-table-column>
            <a-table-column :title="t('adminMinecraft.worldSafety.backupId')" data-index="backup_id" />
            <a-table-column :title="t('adminMinecraft.worldSafety.status')" data-index="status">
              <template #cell="{ record }">
                <a-tag>{{ translateStatus(record.is_expired ? 'expired' : record.status) }}</a-tag>
              </template>
            </a-table-column>
            <a-table-column :title="t('adminMinecraft.worldSafety.phase')" data-index="phase">
              <template #cell="{ record }">{{ record.phase ? translatePhase(record.phase) : '—' }}</template>
            </a-table-column>
            <a-table-column :title="t('adminMinecraft.worldSafety.preRestoreBackup')" data-index="pre_restore_backup_id">
              <template #cell="{ record }">{{ record.pre_restore_backup_id || '—' }}</template>
            </a-table-column>
            <a-table-column :title="t('adminMinecraft.worldSafety.error')" data-index="error_code">
              <template #cell="{ record }">{{ record.error_code || '—' }}</template>
            </a-table-column>
            <a-table-column :title="t('adminMinecraft.worldSafety.createdAt')" data-index="created_at">
              <template #cell="{ record }">{{ formatDate(record.created_at) }}</template>
            </a-table-column>
            <a-table-column :title="t('common.actions')">
              <template #cell="{ record }">
                <a-button v-if="record.resumable" type="text" size="small" @click="continuePlan(record)">
                  {{ t('adminMinecraft.worldSafety.continuePlan') }}
                </a-button>
                <span v-else>—</span>
              </template>
            </a-table-column>
          </template>
          <template #empty>{{ t('adminMinecraft.worldSafety.noPlans') }}</template>
        </a-table>
      </template>
    </a-space>
  </a-card>
</template>

<style scoped>
.world-restore-form {
  max-width: 760px;
}

.recovery-resolution-card {
  border-color: rgb(var(--danger-6));
}
</style>
