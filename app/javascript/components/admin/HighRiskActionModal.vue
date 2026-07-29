<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { Message } from '@mcweb/ui'
import { createIdempotencyKey } from '@/lib/idempotency'
import { HttpError, postJson } from '@/lib/http'

interface PreviewItem {
  label: string
  value: string
}

interface Authorization {
  authorization_token: string
  confirmation: string
  request_id: string
  expires_in: number
  preview_items: PreviewItem[]
}

const props = withDefaults(defineProps<{
  visible: boolean
  title: string
  authorizationUrl: string
  actionUrl: string
  method?: 'POST' | 'PATCH' | 'PUT' | 'DELETE'
  payload?: Record<string, unknown>
}>(), {
  method: 'POST',
  payload: () => ({}),
})

const emit = defineEmits<{
  'update:visible': [value: boolean]
  completed: [result: Record<string, unknown>]
}>()

const { t } = useI18n()
const reason = ref('')
const requestId = ref('')
const confirmation = ref('')
const authorization = ref<Authorization | null>(null)
const authorizing = ref(false)
const submitting = ref(false)
const errorMessage = ref('')

const step = computed(() => authorization.value ? 2 : 1)
const canAuthorize = computed(() =>
  reason.value.trim().length > 0 && !authorizing.value && !submitting.value,
)
const canSubmit = computed(() =>
  Boolean(authorization.value)
  && confirmation.value === authorization.value?.confirmation
  && !authorizing.value
  && !submitting.value,
)

watch(() => props.visible, (visible) => {
  if (visible) reset()
})

function reset() {
  reason.value = ''
  requestId.value = createIdempotencyKey()
  confirmation.value = ''
  authorization.value = null
  errorMessage.value = ''
  authorizing.value = false
  submitting.value = false
}

function close() {
  if (authorizing.value || submitting.value) return
  emit('update:visible', false)
}

function errorText(error: unknown) {
  if (error instanceof HttpError && error.body && typeof error.body === 'object') {
    const message = (error.body as { error?: unknown }).error
    if (typeof message === 'string' && message.length > 0) return message
  }
  return t('admin.highRisk.requestFailed')
}

async function authorize() {
  if (!canAuthorize.value) return

  authorizing.value = true
  errorMessage.value = ''
  try {
    const result = await postJson<Authorization>(props.authorizationUrl, {
      ...props.payload,
      reason: reason.value.trim(),
      request_id: requestId.value,
    })
    authorization.value = result
    requestId.value = result.request_id
    confirmation.value = ''
  } catch (error) {
    errorMessage.value = errorText(error)
  } finally {
    authorizing.value = false
  }
}

function editRequest() {
  if (submitting.value) return
  authorization.value = null
  confirmation.value = ''
  requestId.value = createIdempotencyKey()
  errorMessage.value = ''
}

async function execute() {
  const challenge = authorization.value
  if (!challenge || !canSubmit.value) return

  submitting.value = true
  errorMessage.value = ''
  try {
    const result = await postJson<Record<string, unknown>>(
      props.actionUrl,
      {
        ...props.payload,
        reason: reason.value.trim(),
        request_id: requestId.value,
        authorization_token: challenge.authorization_token,
        confirmation: confirmation.value,
      },
      { method: props.method },
    )
    const message = result.message
    Message.success(
      typeof message === 'string' && message.length > 0
        ? message
        : t('admin.highRisk.completed'),
    )
    emit('completed', result)
    emit('update:visible', false)
  } catch (error) {
    errorMessage.value = errorText(error)
  } finally {
    submitting.value = false
  }
}
</script>

<template>
  <a-modal
    :visible="visible"
    :title="title"
    :footer="false"
    :mask-closable="!authorizing && !submitting"
    :esc-to-close="!authorizing && !submitting"
    :width="'min(600px, calc(100vw - 32px))'"
    @cancel="close"
  >
    <a-steps :current="step" size="small" class="mb-5">
      <a-step :title="t('admin.highRisk.stepReason')" />
      <a-step :title="t('admin.highRisk.stepConfirm')" />
    </a-steps>

    <a-alert
      v-if="errorMessage"
      class="mb-4"
      type="error"
      show-icon
      :closable="false"
    >
      {{ errorMessage }}
    </a-alert>

    <a-alert
      class="mb-5"
      type="warning"
      show-icon
      :closable="false"
      :title="t('admin.highRisk.warningTitle')"
    >
      {{ t('admin.highRisk.warningBody') }}
    </a-alert>

    <a-form layout="vertical">
      <template v-if="!authorization">
        <a-form-item
          field="reason"
          :label="t('admin.highRisk.reason')"
          :extra="t('admin.highRisk.reasonHint')"
          required
        >
          <a-textarea
            v-model="reason"
            :placeholder="t('admin.highRisk.reasonPlaceholder')"
            :auto-size="{ minRows: 3, maxRows: 6 }"
            :max-length="1000"
            show-word-limit
            :disabled="authorizing"
          />
        </a-form-item>

        <div class="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
          <a-button class="w-full sm:w-auto" :disabled="authorizing" @click="close">
            {{ t('common.cancel') }}
          </a-button>
          <a-button
            class="w-full sm:w-auto"
            type="primary"
            status="warning"
            :loading="authorizing"
            :disabled="!canAuthorize"
            @click="authorize"
          >
            {{ t('admin.highRisk.preview') }}
          </a-button>
        </div>
      </template>

      <template v-else>
        <a-descriptions :column="1" bordered size="small" class="mb-4">
          <a-descriptions-item
            v-for="item in authorization.preview_items"
            :key="item.label"
            :label="item.label"
          >
            <span class="break-words">{{ item.value }}</span>
          </a-descriptions-item>
          <a-descriptions-item :label="t('admin.highRisk.requestId')">
            <code class="break-all text-xs">{{ authorization.request_id }}</code>
          </a-descriptions-item>
        </a-descriptions>

        <a-alert type="info" show-icon class="mb-4">
          {{
            t('admin.highRisk.expires', {
              minutes: Math.max(1, Math.ceil(authorization.expires_in / 60)),
            })
          }}
        </a-alert>

        <a-form-item
          field="confirmation"
          :label="t('admin.highRisk.confirmation')"
          required
        >
          <a-input
            v-model="confirmation"
            :placeholder="t('admin.highRisk.confirmationPlaceholder')"
            :disabled="submitting"
            autocomplete="off"
          />
          <template #extra>
            <div class="mt-1 grid gap-2">
              <span>{{ t('admin.highRisk.confirmationHint') }}</span>
              <a-tag color="orangered" class="w-fit max-w-full">
                <code class="break-all">{{ authorization.confirmation }}</code>
              </a-tag>
            </div>
          </template>
        </a-form-item>

        <div class="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
          <a-button class="w-full sm:w-auto" :disabled="submitting" @click="editRequest">
            {{ t('admin.highRisk.backToEdit') }}
          </a-button>
          <a-button
            class="w-full sm:w-auto"
            type="primary"
            status="danger"
            :loading="submitting"
            :disabled="!canSubmit"
            @click="execute"
          >
            {{ t('admin.highRisk.execute') }}
          </a-button>
        </div>
      </template>
    </a-form>
  </a-modal>
</template>
