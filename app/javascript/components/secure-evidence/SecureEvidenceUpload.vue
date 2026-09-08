<script setup lang="ts">
import { onBeforeUnmount, ref, watch } from 'vue'
import { Alert, Button, Space, TypographyText } from '@mcweb/ui'
import { IconAttachment } from '@arco-design/web-vue/es/icon'
import { csrfHeaders } from '@/lib/csrf'
import { createIdempotencyKey } from '@/lib/idempotency'
import type {
  SecureEvidenceAttachment,
  SecureEvidenceUploadCopy,
} from '@/types/secureEvidence'

const props = defineProps<{
  uploadUrl: string
  subjectKey: string
  subjectPublicId: string
  copy: SecureEvidenceUploadCopy
  disabled?: boolean
}>()

const emit = defineEmits<{
  uploaded: [attachment: SecureEvidenceAttachment]
}>()

const input = ref<HTMLInputElement | null>(null)
const busy = ref(false)
const error = ref('')
const retryKeys = new Map<string, string>()
const UPLOAD_REQUEST_TIMEOUT_MS = 60_000
const SCAN_REQUEST_TIMEOUT_MS = 10_000
const SCAN_DEADLINE_MS = 90_000
let activeController: AbortController | null = null
let operationRevision = 0
let disposed = false

onBeforeUnmount(() => {
  disposed = true
  operationRevision += 1
  activeController?.abort()
  activeController = null
  retryKeys.clear()
})

watch(
  () => [props.uploadUrl, props.subjectKey, props.subjectPublicId],
  () => {
    operationRevision += 1
    activeController?.abort()
    activeController = null
    busy.value = false
    error.value = ''
    if (input.value) input.value.value = ''
  },
)

function openPicker() {
  if (!busy.value && !props.disabled) input.value?.click()
}

async function onChange(event: Event) {
  const element = event.target as HTMLInputElement
  const file = element.files?.[0]
  if (!file) return

  activeController?.abort()
  const controller = new AbortController()
  activeController = controller
  const revision = ++operationRevision
  const uploadUrl = props.uploadUrl
  const subjectKey = props.subjectKey
  const subjectPublicId = props.subjectPublicId
  busy.value = true
  error.value = ''
  const retryKey = [
    subjectKey,
    subjectPublicId,
    file.name,
    file.size,
    file.lastModified,
  ].join(':')
  const idempotencyKey = retryKeys.get(retryKey) || createIdempotencyKey()
  retryKeys.set(retryKey, idempotencyKey)
  try {
    const body = new FormData()
    body.append('subject_key', subjectKey)
    body.append('subject_public_id', subjectPublicId)
    body.append('idempotency_key', idempotencyKey)
    body.append('file', file)
    const response = await fetchWithTimeout(
      uploadUrl,
      {
        method: 'POST',
        headers: { ...csrfHeaders(), Accept: 'application/json' },
        credentials: 'same-origin',
        body,
      },
      controller.signal,
      UPLOAD_REQUEST_TIMEOUT_MS,
      props.copy.uploadFailed,
    )
    const payload = await responsePayload(response)
    if (!response.ok) {
      throw new Error(payloadMessage(payload) || props.copy.uploadFailed)
    }
    const attachment = attachmentPayload(payload)
    if (!attachment) throw new Error(props.copy.uploadFailed)

    const scannedAttachment = await waitForScan(attachment, controller.signal)
    if (
      !disposed
      && activeController === controller
      && operationRevision === revision
      && props.uploadUrl === uploadUrl
      && props.subjectKey === subjectKey
      && props.subjectPublicId === subjectPublicId
    ) {
      retryKeys.delete(retryKey)
      emit('uploaded', scannedAttachment)
    }
  } catch (cause) {
    if (disposed || controller.signal.aborted) return
    error.value = cause instanceof Error && cause.message
      ? cause.message
      : props.copy.uploadFailed
  } finally {
    if (
      !disposed
      && activeController === controller
      && operationRevision === revision
    ) {
      activeController = null
      busy.value = false
      element.value = ''
    }
  }
}

async function waitForScan(
  initial: SecureEvidenceAttachment,
  signal: AbortSignal,
): Promise<SecureEvidenceAttachment> {
  if (initial.state === 'available' && initial.scan_status === 'clean') return initial
  if (initial.state === 'upload_failed') throw new Error(props.copy.uploadFailed)
  if (!initial.scan_status_url) throw new Error(props.copy.scanFailed)

  const deadline = Date.now() + SCAN_DEADLINE_MS
  for (let attempt = 0; attempt < 90; attempt += 1) {
    const delayBudget = deadline - Date.now()
    if (delayBudget <= 0) break
    await abortableDelay(Math.min(1000, delayBudget), signal)
    const requestBudget = deadline - Date.now()
    if (requestBudget <= 0) break
    const response = await fetchWithTimeout(
      initial.scan_status_url,
      {
        headers: { Accept: 'application/json' },
        credentials: 'same-origin',
      },
      signal,
      Math.min(SCAN_REQUEST_TIMEOUT_MS, requestBudget),
      props.copy.scanFailed,
    )
    if (!response.ok) throw new Error(props.copy.scanFailed)
    const payload = attachmentPayload(await responsePayload(response))
    if (!payload) throw new Error(props.copy.scanFailed)
    if (payload.public_id !== initial.public_id) throw new Error(props.copy.scanFailed)
    if (payload.state === 'available' && payload.scan_status === 'clean') return payload
    if (payload.state === 'upload_failed') throw new Error(props.copy.uploadFailed)
    if (['quarantined', 'purge_pending', 'purged'].includes(payload.state)) {
      throw new Error(props.copy.scanFailed)
    }
  }
  throw new Error(props.copy.scanTimeout)
}

async function fetchWithTimeout(
  input: RequestInfo | URL,
  init: RequestInit,
  operationSignal: AbortSignal,
  timeoutMs: number,
  timeoutMessage: string,
): Promise<Response> {
  const requestController = new AbortController()
  let timedOut = false
  const abortRequest = () => requestController.abort()
  operationSignal.addEventListener('abort', abortRequest, { once: true })
  if (operationSignal.aborted) abortRequest()
  const timeout = window.setTimeout(() => {
    timedOut = true
    requestController.abort()
  }, timeoutMs)
  try {
    return await fetch(input, { ...init, signal: requestController.signal })
  } catch (cause) {
    if (timedOut) throw new Error(timeoutMessage)
    throw cause
  } finally {
    window.clearTimeout(timeout)
    operationSignal.removeEventListener('abort', abortRequest)
  }
}

function abortableDelay(milliseconds: number, signal: AbortSignal): Promise<void> {
  return new Promise((resolve, reject) => {
    if (signal.aborted) {
      reject(new DOMException('Aborted', 'AbortError'))
      return
    }
    const timeout = window.setTimeout(() => {
      signal.removeEventListener('abort', onAbort)
      resolve()
    }, milliseconds)
    function onAbort() {
      window.clearTimeout(timeout)
      reject(new DOMException('Aborted', 'AbortError'))
    }
    signal.addEventListener('abort', onAbort, { once: true })
  })
}

async function responsePayload(response: Response): Promise<unknown> {
  try {
    return await response.json()
  } catch {
    return null
  }
}

function payloadMessage(payload: unknown): string {
  if (!payload || typeof payload !== 'object') return ''
  const record = payload as Record<string, unknown>
  const value = record.message || record.error
  return typeof value === 'string' ? value : ''
}

function attachmentPayload(payload: unknown): SecureEvidenceAttachment | null {
  if (!payload || typeof payload !== 'object') return null
  const record = payload as Partial<SecureEvidenceAttachment>
  if (
    typeof record.public_id !== 'string'
    || !record.public_id
    || typeof record.filename !== 'string'
    || typeof record.byte_size !== 'number'
    || !Number.isFinite(record.byte_size)
    || record.byte_size < 0
    || typeof record.state !== 'string'
    || (record.scan_status !== null && typeof record.scan_status !== 'string')
    || typeof record.scan_status_url !== 'string'
    || typeof record.download_url !== 'string'
  ) return null

  return record as SecureEvidenceAttachment
}
</script>

<template>
  <Space direction="vertical" fill size="small">
    <input
      ref="input"
      type="file"
      hidden
      :disabled="busy || disabled"
      @change="onChange"
    >
    <Button type="outline" :loading="busy" :disabled="busy || disabled" @click="openPicker">
      <template #icon><IconAttachment /></template>
      {{ busy ? copy.processing : copy.add }}
    </Button>
    <TypographyText type="secondary">{{ copy.limit }}</TypographyText>
    <Alert v-if="error" type="error" show-icon aria-live="polite">{{ error }}</Alert>
  </Space>
</template>
