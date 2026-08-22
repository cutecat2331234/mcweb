<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import {
  Alert,
  Button,
  Card,
  Descriptions,
  DescriptionsItem,
  Form,
  FormItem,
  Grid,
  GridItem,
  Input,
  InputNumber,
  Modal,
  Space,
  Steps,
  Step,
  Table,
  TableColumn,
  Tag,
  Textarea,
  TypographyText,
} from '@mcweb/ui'
import { createIdempotencyKey } from '@/lib/idempotency'
import { HttpError, postJson } from '@/lib/http'

type PreviewItem = {
  case_id: number
  status?: string
  message?: string
  [key: string]: unknown
}

type AuthorizationResponse = {
  authorization_token: string
  typed_confirmation: string
  expires_at: string
  preview: PreviewItem[]
}

export type ModerationActionResult = {
  case_id: number
  status: string
  message: string
}

export type ModerationExecutionResponse = {
  request_id: string
  replayed: boolean
  results: ModerationActionResult[]
}

const props = withDefaults(defineProps<{
  visible: boolean
  action: string
  caseIds: number[]
  attributes?: Record<string, unknown>
  authorizeUrl?: string
  executeUrl?: string
}>(), {
  attributes: () => ({}),
  authorizeUrl: '/admin/forum/moderation-workbench/authorize-action',
  executeUrl: '/admin/forum/moderation-workbench/execute-action',
})

const emit = defineEmits<{
  'update:visible': [value: boolean]
  completed: [result: ModerationExecutionResponse]
}>()

const { locale, t } = useI18n()
const reason = ref('')
const typedConfirmation = ref('')
const requestId = ref('')
const authorization = ref<AuthorizationResponse | null>(null)
const execution = ref<ModerationExecutionResponse | null>(null)
const authorizing = ref(false)
const executing = ref(false)
const errorMessage = ref('')
const warningPoints = ref(1)
const warningExpireDays = ref(90)
const durationDays = ref(7)

const currentStep = computed(() => {
  if (execution.value) return 3
  if (authorization.value) return 2
  return 1
})
const modalTitle = computed(() => {
  if (!props.visible || !props.action) return ''

  return t('admin.moderationWorkbench.actionModal.title', {
    action: t(`admin.moderationWorkbench.actions.${props.action}`),
    count: props.caseIds.length,
  })
})
const canPreview = computed(() =>
  props.action.length > 0 &&
  props.caseIds.length > 0 &&
  reason.value.trim().length >= (props.action === 'release_attachment' ? 12 : 10) &&
  actionAttributesValid.value &&
  !authorizing.value &&
  !executing.value,
)
const canExecute = computed(() =>
  Boolean(authorization.value) &&
  typedConfirmation.value === authorization.value?.typed_confirmation &&
  !authorizing.value &&
  !executing.value,
)
const actionAttributes = computed<Record<string, unknown>>(() => {
  const attributes = { ...props.attributes }
  if (props.action === 'warn_user') {
    attributes.points = warningPoints.value
    attributes.expire_days = warningExpireDays.value
  }
  if (props.action === 'mute_user' || props.action === 'ban_user') {
    attributes.duration_days = durationDays.value
  }
  return attributes
})
const actionAttributesValid = computed(() => {
  if (props.action === 'warn_user') {
    return warningPoints.value >= 1 &&
      warningPoints.value <= 10 &&
      warningExpireDays.value >= 0 &&
      warningExpireDays.value <= 3650
  }
  if (props.action === 'mute_user') {
    return durationDays.value >= 1 && durationDays.value <= 3650
  }
  if (props.action === 'ban_user') {
    return durationDays.value >= 0 && durationDays.value <= 3650
  }
  return true
})

watch(
  () => props.visible,
  (visible) => {
    if (visible) reset()
  },
)

watch(
  () => [warningPoints.value, warningExpireDays.value, durationDays.value],
  () => {
    if (!props.visible || (!authorization.value && !execution.value)) return
    authorization.value = null
    execution.value = null
    typedConfirmation.value = ''
    requestId.value = createIdempotencyKey()
    errorMessage.value = ''
  },
)

watch(
  () => [props.action, ...props.caseIds],
  () => {
    if (!props.visible || (!authorization.value && !execution.value)) return
    authorization.value = null
    execution.value = null
    typedConfirmation.value = ''
    requestId.value = createIdempotencyKey()
    errorMessage.value = ''
  },
)

function reset() {
  reason.value = ''
  typedConfirmation.value = ''
  requestId.value = createIdempotencyKey()
  authorization.value = null
  execution.value = null
  authorizing.value = false
  executing.value = false
  errorMessage.value = ''
  warningPoints.value = 1
  warningExpireDays.value = 90
  durationDays.value = 7
}

function close() {
  if (authorizing.value || executing.value) return
  emit('update:visible', false)
}

function requestError(error: unknown) {
  if (error instanceof HttpError && error.body && typeof error.body === 'object') {
    const body = error.body as { error?: unknown; message?: unknown }
    if (typeof body.error === 'string' && body.error.length > 0) return body.error
    if (typeof body.message === 'string' && body.message.length > 0) return body.message
  }
  return t('admin.moderationWorkbench.actionModal.requestFailed')
}

function formatTime(value: string) {
  return new Intl.DateTimeFormat(locale.value, {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(value))
}

function displayPreviewValue(value: unknown) {
  if (value === null || value === undefined || value === '') {
    return t('admin.moderationWorkbench.common.notAvailable')
  }
  if (typeof value === 'object') return JSON.stringify(value)
  return String(value)
}

function previewFields(item: PreviewItem) {
  return Object.entries(item).filter(([key]) => key !== 'case_id')
}

function resultColor(status: string) {
  if (['success', 'completed', 'ok'].includes(status)) return 'green'
  if (['skipped', 'conflict'].includes(status)) return 'orange'
  return 'red'
}

async function authorize() {
  if (!canPreview.value) return

  authorizing.value = true
  errorMessage.value = ''
  try {
    authorization.value = await postJson<AuthorizationResponse>(props.authorizeUrl, {
      action: props.action,
      case_ids: props.caseIds,
      reason: reason.value.trim(),
      attributes: actionAttributes.value,
      request_id: requestId.value,
    })
    typedConfirmation.value = ''
  } catch (error) {
    errorMessage.value = requestError(error)
  } finally {
    authorizing.value = false
  }
}

function editRequest() {
  if (executing.value) return
  authorization.value = null
  typedConfirmation.value = ''
  requestId.value = createIdempotencyKey()
  errorMessage.value = ''
}

async function execute() {
  const challenge = authorization.value
  if (!challenge || !canExecute.value) return

  executing.value = true
  errorMessage.value = ''
  try {
    execution.value = await postJson<ModerationExecutionResponse>(props.executeUrl, {
      action: props.action,
      case_ids: props.caseIds,
      reason: reason.value.trim(),
      attributes: actionAttributes.value,
      request_id: requestId.value,
      authorization_token: challenge.authorization_token,
      typed_confirmation: typedConfirmation.value,
    })
    emit('completed', execution.value)
  } catch (error) {
    errorMessage.value = requestError(error)
  } finally {
    executing.value = false
  }
}
</script>

<template>
  <Modal
    :visible="visible"
    :title="modalTitle"
    :footer="false"
    :mask-closable="!authorizing && !executing"
    :esc-to-close="!authorizing && !executing"
    :width="'min(720px, calc(100vw - 24px))'"
    @cancel="close"
  >
    <Steps :current="currentStep" size="small">
      <Step :title="t('admin.moderationWorkbench.actionModal.steps.reason')" />
      <Step :title="t('admin.moderationWorkbench.actionModal.steps.confirm')" />
      <Step :title="t('admin.moderationWorkbench.actionModal.steps.results')" />
    </Steps>

    <Alert
      v-if="errorMessage"
      type="error"
      show-icon
      :closable="false"
    >
      {{ errorMessage }}
    </Alert>

    <template v-if="execution">
      <Alert
        :type="execution.results.every((item) => resultColor(item.status) === 'green') ? 'success' : 'warning'"
        show-icon
        :closable="false"
        :title="execution.replayed
          ? t('admin.moderationWorkbench.actionModal.replayed')
          : t('admin.moderationWorkbench.actionModal.completed')"
      />

      <Descriptions :column="1" bordered size="small">
        <DescriptionsItem :label="t('admin.moderationWorkbench.actionModal.requestId')">
          <TypographyText code copyable>{{ execution.request_id }}</TypographyText>
        </DescriptionsItem>
      </Descriptions>

      <Table
        :data="execution.results"
        :pagination="false"
        :bordered="{ wrapper: true }"
        :scroll="{ minWidth: 560, maxHeight: 420 }"
        row-key="case_id"
      >
        <template #columns>
          <TableColumn
            :title="t('admin.moderationWorkbench.actionModal.case')"
            data-index="case_id"
            :width="110"
          />
          <TableColumn
            :title="t('admin.moderationWorkbench.actionModal.status')"
            :width="140"
          >
            <template #cell="{ record }">
              <Tag :color="resultColor(record.status)">
                {{ t(`admin.moderationWorkbench.resultStatuses.${record.status}`) }}
              </Tag>
            </template>
          </TableColumn>
          <TableColumn
            :title="t('admin.moderationWorkbench.actionModal.message')"
            data-index="message"
            :width="310"
          />
        </template>
      </Table>

      <Button type="primary" long @click="close">
        {{ t('admin.moderationWorkbench.actionModal.done') }}
      </Button>
    </template>

    <Form v-else layout="vertical">
      <template v-if="!authorization">
        <Alert
          type="warning"
          show-icon
          :closable="false"
          :title="t('admin.moderationWorkbench.actionModal.warning')"
        />

        <FormItem
          field="reason"
          :label="t('admin.moderationWorkbench.actionModal.reason')"
          :extra="t('admin.moderationWorkbench.actionModal.reasonHint')"
          required
        >
          <Textarea
            v-model="reason"
            :placeholder="t('admin.moderationWorkbench.actionModal.reasonPlaceholder')"
            :auto-size="{ minRows: 4, maxRows: 8 }"
            :max-length="1000"
            show-word-limit
            :disabled="authorizing"
          />
        </FormItem>

        <Grid v-if="action === 'warn_user'" :cols="{ xs: 1, sm: 2 }" :col-gap="12">
          <GridItem>
            <FormItem
              field="points"
              :label="t('admin.moderationWorkbench.actionModal.warningPoints')"
              required
            >
              <InputNumber
                v-model="warningPoints"
                :min="1"
                :max="10"
                long
                :disabled="authorizing"
              />
            </FormItem>
          </GridItem>
          <GridItem>
            <FormItem
              field="expire_days"
              :label="t('admin.moderationWorkbench.actionModal.warningExpireDays')"
              required
            >
              <InputNumber
                v-model="warningExpireDays"
                :min="0"
                :max="3650"
                long
                :disabled="authorizing"
              />
            </FormItem>
          </GridItem>
        </Grid>

        <FormItem
          v-if="action === 'mute_user' || action === 'ban_user'"
          field="duration_days"
          :label="t('admin.moderationWorkbench.actionModal.durationDays')"
          :extra="action === 'ban_user'
            ? t('admin.moderationWorkbench.actionModal.permanentBanHint')
            : undefined"
          required
        >
          <InputNumber
            v-model="durationDays"
            :min="action === 'ban_user' ? 0 : 1"
            :max="3650"
            long
            :disabled="authorizing"
          />
        </FormItem>

        <Grid :cols="{ xs: 1, sm: 2 }" :col-gap="8" :row-gap="8">
          <GridItem>
            <Button long :disabled="authorizing" @click="close">
              {{ t('admin.moderationWorkbench.common.cancel') }}
            </Button>
          </GridItem>
          <GridItem>
            <Button
              type="primary"
              status="warning"
              long
              :loading="authorizing"
              :disabled="!canPreview"
              @click="authorize"
            >
              {{ t('admin.moderationWorkbench.actionModal.preview') }}
            </Button>
          </GridItem>
        </Grid>
      </template>

      <template v-else>
        <Alert
          type="info"
          show-icon
          :closable="false"
          :title="t('admin.moderationWorkbench.actionModal.expiresAt', {
            time: formatTime(authorization.expires_at),
          })"
        />

        <Space direction="vertical" :size="12" fill>
          <Card
            v-for="item in authorization.preview"
            :key="item.case_id"
            :bordered="true"
            size="small"
          >
            <template #title>
              {{ t('admin.moderationWorkbench.actionModal.caseWithId', { id: item.case_id }) }}
            </template>
            <Descriptions :column="1" size="small">
              <DescriptionsItem
                v-for="[key, value] in previewFields(item)"
                :key="key"
                :label="t(`admin.moderationWorkbench.preview.${key}`)"
              >
                <TypographyText>{{ displayPreviewValue(value) }}</TypographyText>
              </DescriptionsItem>
            </Descriptions>
          </Card>
        </Space>

        <FormItem
          field="typed_confirmation"
          :label="t('admin.moderationWorkbench.actionModal.typedConfirmation')"
          required
        >
          <Input
            v-model="typedConfirmation"
            :placeholder="t('admin.moderationWorkbench.actionModal.typedConfirmationPlaceholder')"
            :disabled="executing"
            autocomplete="off"
          />
          <template #extra>
            <Space direction="vertical" :size="8" fill>
              <TypographyText type="secondary">
                {{ t('admin.moderationWorkbench.actionModal.typedConfirmationHint') }}
              </TypographyText>
              <Tag color="orangered">
                <TypographyText code copyable>{{ authorization.typed_confirmation }}</TypographyText>
              </Tag>
            </Space>
          </template>
        </FormItem>

        <Grid :cols="{ xs: 1, sm: 2 }" :col-gap="8" :row-gap="8">
          <GridItem>
            <Button long :disabled="executing" @click="editRequest">
              {{ t('admin.moderationWorkbench.actionModal.back') }}
            </Button>
          </GridItem>
          <GridItem>
            <Button
              type="primary"
              status="danger"
              long
              :loading="executing"
              :disabled="!canExecute"
              @click="execute"
            >
              {{ t('admin.moderationWorkbench.actionModal.execute') }}
            </Button>
          </GridItem>
        </Grid>
      </template>
    </Form>
  </Modal>
</template>
