<script setup lang="ts">
import { ref } from 'vue'
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

function openPicker() {
  if (!busy.value && !props.disabled) input.value?.click()
}

async function onChange(event: Event) {
  const element = event.target as HTMLInputElement
  const file = element.files?.[0]
  if (!file) return

  busy.value = true
  error.value = ''
  const retryKey = [
    props.subjectKey,
    props.subjectPublicId,
    file.name,
    file.size,
    file.lastModified,
  ].join(':')
  const idempotencyKey = retryKeys.get(retryKey) || createIdempotencyKey()
  retryKeys.set(retryKey, idempotencyKey)
  try {
    const body = new FormData()
    body.append('subject_key', props.subjectKey)
    body.append('subject_public_id', props.subjectPublicId)
    body.append('idempotency_key', idempotencyKey)
    body.append('file', file)
    const response = await fetch(props.uploadUrl, {
      method: 'POST',
      headers: { ...csrfHeaders(), Accept: 'application/json' },
      credentials: 'same-origin',
      body,
    })
    const payload = await response.json()
    if (!response.ok) throw new Error(payload.message || payload.error)

    const attachment = await waitForScan(payload as SecureEvidenceAttachment)
    if (attachment) {
      retryKeys.delete(retryKey)
      emit('uploaded', attachment)
    }
  } catch (cause) {
    error.value = cause instanceof Error && cause.message
      ? cause.message
      : props.copy.uploadFailed
  } finally {
    busy.value = false
    element.value = ''
  }
}

async function waitForScan(initial: SecureEvidenceAttachment) {
  if (initial.state === 'available' && initial.scan_status === 'clean') return initial
  if (initial.state === 'upload_failed') throw new Error(props.copy.uploadFailed)

  for (let attempt = 0; attempt < 90; attempt += 1) {
    await new Promise((resolve) => window.setTimeout(resolve, 1000))
    const response = await fetch(initial.scan_status_url, {
      headers: { Accept: 'application/json' },
      credentials: 'same-origin',
    })
    if (!response.ok) throw new Error(props.copy.scanFailed)
    const payload = await response.json() as SecureEvidenceAttachment
    if (payload.state === 'available' && payload.scan_status === 'clean') return payload
    if (payload.state === 'upload_failed') throw new Error(props.copy.uploadFailed)
    if (['quarantined', 'purge_pending', 'purged'].includes(payload.state)) {
      throw new Error(props.copy.scanFailed)
    }
  }
  throw new Error(props.copy.scanTimeout)
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
