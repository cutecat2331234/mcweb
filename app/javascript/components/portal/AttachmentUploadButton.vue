<script setup lang="ts">
import { ref } from 'vue'
import { usePage } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import Button from '@/components/ui/Button.vue'
import { routes } from '@/lib/routes'
import { csrfHeaders } from '@/lib/csrf'

export type PendingAttachment = {
  id: number
  filename: string
  human_size: string
  download_url: string
  scan_status?: string
  scan_status_url?: string
}

const props = defineProps<{
  disabled?: boolean
}>()

const emit = defineEmits<{
  uploaded: [attachment: PendingAttachment]
}>()

const { t } = useI18n()
const page = usePage()
const fileInput = ref<HTMLInputElement | null>(null)
const uploading = ref(false)
const scanning = ref(false)
const error = ref('')

const canUpload = () => {
  const user = (page.props.auth as { user?: { can_upload_attachments?: boolean } } | undefined)?.user
  return user?.can_upload_attachments === true
}

function openPicker() {
  if (!canUpload()) return
  fileInput.value?.click()
}

async function onFileChange(event: Event) {
  const input = event.target as HTMLInputElement
  const file = input.files?.[0]
  if (!file) return

  uploading.value = true
  error.value = ''
  try {
    const form = new FormData()
    form.append('file', file)
    const res = await fetch(routes.forumAttachments, {
      method: 'POST',
      headers: { ...csrfHeaders(), Accept: 'application/json' },
      body: form,
      credentials: 'same-origin',
    })
    const data = await res.json()
    if (!res.ok) {
      error.value = data.error || t('components.attachmentUpload.uploadFailed')
      return
    }
    const attachment = data as PendingAttachment
    if (attachment.scan_status === 'clean') {
      emit('uploaded', attachment)
      return
    }

    const scannedAttachment = await waitForCleanScan(attachment)
    if (scannedAttachment) emit('uploaded', scannedAttachment)
  } catch {
    error.value = t('components.attachmentUpload.uploadFailed')
  } finally {
    scanning.value = false
    uploading.value = false
    input.value = ''
  }
}

async function waitForCleanScan(attachment: PendingAttachment) {
  if (!attachment.scan_status_url) {
    error.value = t('components.attachmentUpload.scanFailed')
    return null
  }

  scanning.value = true
  for (let attempt = 0; attempt < 90; attempt += 1) {
    await new Promise((resolve) => window.setTimeout(resolve, 1000))
    const response = await fetch(attachment.scan_status_url, {
      headers: { Accept: 'application/json' },
      credentials: 'same-origin',
    })
    if (!response.ok) {
      error.value = t('components.attachmentUpload.scanFailed')
      return null
    }

    const status = await response.json()
    if (status.scan_status === 'clean' && status.attachment) {
      return status.attachment as PendingAttachment
    }
    if (status.scan_status === 'infected' || (status.scan_status === 'error' && !status.retryable)) {
      error.value = t('components.attachmentUpload.scanFailed')
      return null
    }
  }

  error.value = t('components.attachmentUpload.scanTimeout')
  return null
}
</script>

<template>
  <div v-if="canUpload()" class="inline-flex flex-col gap-1">
    <input
      ref="fileInput"
      type="file"
      class="hidden"
      :disabled="uploading || disabled"
      @change="onFileChange"
    >
    <Button type="button" variant="outline" size="sm" :disabled="uploading || disabled" @click="openPicker">
      {{
        scanning
          ? t('components.attachmentUpload.scanning')
          : uploading
            ? t('components.attachmentUpload.uploading')
            : t('components.attachmentUpload.addAttachment')
      }}
    </Button>
    <p v-if="error" class="text-xs text-destructive">{{ error }}</p>
  </div>
</template>
