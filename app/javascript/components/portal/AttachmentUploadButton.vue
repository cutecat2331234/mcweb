<script setup lang="ts">
import { ref } from 'vue'
import { usePage } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import Button from '@/components/ui/Button.vue'
import { routes } from '@/lib/routes'

export type PendingAttachment = {
  id: number
  filename: string
  human_size: string
  download_url: string
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
    const token = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content
    const form = new FormData()
    form.append('file', file)
    const res = await fetch(routes.forumAttachments, {
      method: 'POST',
      headers: { 'X-CSRF-Token': token || '', Accept: 'application/json' },
      body: form,
      credentials: 'same-origin',
    })
    const data = await res.json()
    if (!res.ok) {
      error.value = data.error || t('components.attachmentUpload.uploadFailed')
      return
    }
    emit('uploaded', data as PendingAttachment)
  } finally {
    uploading.value = false
    input.value = ''
  }
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
      {{ uploading ? t('components.attachmentUpload.uploading') : t('components.attachmentUpload.addAttachment') }}
    </Button>
    <p v-if="error" class="text-xs text-destructive">{{ error }}</p>
  </div>
</template>
