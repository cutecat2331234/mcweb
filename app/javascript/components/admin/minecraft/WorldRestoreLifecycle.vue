<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import { Message, Modal } from '@mcweb/ui'
import { createIdempotencyKey } from '@/lib/idempotency'
import { HttpError, postJson } from '@/lib/http'
import type {
  WorldRestorePlanRow,
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
const planning = ref(false)
const authorizing = ref(false)
const executing = ref(false)
const creatingBackup = ref(false)
const executionQueued = ref(false)
const errorMessage = ref('')

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
  && password.value.length > 0
  && !authorizing.value
))
const canExecute = computed(() => (
  Boolean(plan.value?.execute_url)
  && authorizationToken.value.length > 0
  && confirmation.value === requiredConfirmation.value
  && !executing.value
  && !executionQueued.value
))

watch([selectedBackupId, reason], () => {
  if (!plan.value) requestId.value = createIdempotencyKey()
})

function initialOwnedPlan() {
  return props.model.plans.find((candidate) => (
    ['planned', 'authorized'].includes(candidate.status) && Boolean(candidate.authorize_url)
    && new Date(candidate.expires_at || '').getTime() > Date.now()
  )) || null
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

function refresh() {
  router.reload({ only: ['worldSafety'], preserveScroll: true })
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
    password.value = ''
    verificationCode.value = ''
  } catch (error) {
    errorMessage.value = errorText(error)
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
    errorMessage.value = errorText(error)
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
    errorMessage.value = errorText(error)
  } finally {
    executing.value = false
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

      <template v-if="model.can_restore">
        <a-divider />
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

          <template v-else-if="!authorizationToken && !executionQueued">
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

          <template v-else-if="!executionQueued">
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
        </a-form>

        <a-table :data="model.plans" :pagination="false" row-key="id" :scroll="{ x: 900 }">
          <template #columns>
            <a-table-column :title="t('adminMinecraft.worldSafety.planId')" data-index="id">
              <template #cell="{ record }"><a-typography-text code>{{ record.id }}</a-typography-text></template>
            </a-table-column>
            <a-table-column :title="t('adminMinecraft.worldSafety.backupId')" data-index="backup_id" />
            <a-table-column :title="t('adminMinecraft.worldSafety.status')" data-index="status">
              <template #cell="{ record }"><a-tag>{{ translateStatus(record.status) }}</a-tag></template>
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
</style>
