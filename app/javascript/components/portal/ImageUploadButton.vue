<script setup lang="ts">
import { ref } from 'vue'
import { useI18n } from 'vue-i18n'
import Button from '@/components/ui/Button.vue'
import { routes } from '@/lib/routes'

const { t } = useI18n()

defineProps<{
  disabled?: boolean
}>()

const emit = defineEmits<{
  insert: [markdown: string]
}>()

const fileInput = ref<HTMLInputElement | null>(null)
const uploading = ref(false)
const error = ref('')

function openPicker() {
  fileInput.value?.click()
}

async function onFileChange(event: Event) {
  const input = event.target as HTMLInputElement
  const files = Array.from(input.files ?? [])
  if (!files.length) return

  uploading.value = true
  error.value = ''
  try {
    const token = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content
    for (const file of files) {
      const form = new FormData()
      form.append('file', file)
      const res = await fetch(routes.forumUpload, {
        method: 'POST',
        headers: { 'X-CSRF-Token': token || '', Accept: 'application/json' },
        body: form,
        credentials: 'same-origin',
      })
      const data = await res.json()
      if (!res.ok) {
        error.value = data.error || t('components.imageUpload.uploadFailed')
        break
      }
      emit('insert', data.markdown)
    }
  } finally {
    uploading.value = false
    input.value = ''
  }
}
</script>

<template>
  <div class="inline-flex flex-col gap-1">
    <input
      ref="fileInput"
      type="file"
      accept="image/jpeg,image/png,image/gif,image/webp"
      multiple
      class="hidden"
      :disabled="uploading || disabled"
      @change="onFileChange"
    >
    <Button type="button" variant="outline" size="sm" :disabled="uploading || disabled" @click="openPicker">
      {{ uploading ? t('components.imageUpload.uploading') : t('components.imageUpload.insertImage') }}
    </Button>
    <p v-if="error" class="text-xs text-destructive">{{ error }}</p>
  </div>
</template>
