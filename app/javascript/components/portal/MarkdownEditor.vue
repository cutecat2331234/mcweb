<script setup lang="ts">
import { ref, computed, nextTick } from 'vue'
import { usePage } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import Button from '@/components/ui/Button.vue'
import MentionAutocomplete from '@/components/portal/MentionAutocomplete.vue'
import ImageUploadButton from '@/components/portal/ImageUploadButton.vue'
import { routes } from '@/lib/routes'

const props = withDefaults(defineProps<{
  modelValue: string
  rows?: number
  placeholder?: string
  required?: boolean
  showImageUpload?: boolean
  showMention?: boolean
}>(), {
  rows: 6,
  showImageUpload: true,
  showMention: true,
})

const emit = defineEmits<{
  'update:modelValue': [value: string]
}>()

const previewHtml = ref<string | null>(null)
const previewLoading = ref(false)
const { t } = useI18n()
const page = usePage()
const canUploadImages = computed(() => {
  const user = (page.props.auth as { user?: { can_upload_images?: boolean } } | undefined)?.user
  return user?.can_upload_images === true
})

const textareaEl = ref<HTMLTextAreaElement | null>(null)

function update(value: string) {
  emit('update:modelValue', value)
}

function restoreSelection(el: HTMLTextAreaElement, start: number, end: number) {
  nextTick(() => {
    el.focus()
    el.setSelectionRange(start, end)
  })
}

// Wrap the current selection (or insert markers at the caret) instead of appending
// to the end, matching XenForo/Discourse composer behaviour.
function wrap(before: string, after: string) {
  const value = props.modelValue
  const el = textareaEl.value
  if (!el) {
    emit('update:modelValue', `${value}${before}${after}`)
    return
  }

  const start = el.selectionStart ?? value.length
  const end = el.selectionEnd ?? value.length
  const selected = value.slice(start, end)
  emit('update:modelValue', value.slice(0, start) + before + selected + after + value.slice(end))
  // Keep the selection wrapped (or place the caret between the markers when nothing was selected).
  restoreSelection(el, start + before.length, start + before.length + selected.length)
}

function insertImage(markdown: string) {
  const value = props.modelValue
  const el = textareaEl.value
  if (!el) {
    emit('update:modelValue', `${value}${value ? '\n\n' : ''}${markdown}`)
    return
  }

  const start = el.selectionStart ?? value.length
  const end = el.selectionEnd ?? value.length
  const prefix = start > 0 && value[start - 1] !== '\n' ? '\n' : ''
  const inserted = `${prefix}${markdown}`
  emit('update:modelValue', value.slice(0, start) + inserted + value.slice(end))
  restoreSelection(el, start + inserted.length, start + inserted.length)
}

const uploadingImage = ref(false)

async function uploadImageFile(file: File) {
  if (!canUploadImages.value || uploadingImage.value) return
  uploadingImage.value = true
  try {
    const token = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content
    const form = new FormData()
    form.append('file', file)
    const res = await fetch(routes.forumUpload, {
      method: 'POST',
      headers: { 'X-CSRF-Token': token || '', Accept: 'application/json' },
      body: form,
      credentials: 'same-origin',
    })
    const data = await res.json()
    if (res.ok && data.markdown) insertImage(data.markdown)
  } finally {
    uploadingImage.value = false
  }
}

function handlePaste(event: ClipboardEvent) {
  if (!canUploadImages.value) return
  const items = event.clipboardData?.items
  if (!items) return
  for (let i = 0; i < items.length; i++) {
    const item = items[i]
    if (item.kind === 'file' && item.type.startsWith('image/')) {
      const file = item.getAsFile()
      if (file) {
        event.preventDefault()
        uploadImageFile(file)
        return
      }
    }
  }
}

function handleDrop(event: DragEvent) {
  if (!canUploadImages.value) return
  const image = Array.from(event.dataTransfer?.files ?? []).find((f) => f.type.startsWith('image/'))
  if (image) {
    event.preventDefault()
    uploadImageFile(image)
  }
}

function handleDragOver(event: DragEvent) {
  if (canUploadImages.value && Array.from(event.dataTransfer?.types ?? []).includes('Files')) {
    event.preventDefault()
  }
}

const showEmoji = ref(false)
const emojis = ['😀', '😂', '😍', '👍', '👎', '🎉', '❤️', '🔥', '😢', '😡', '🤔', '👀', '🙏', '💯', '✅', '❌', '🚀', '😎', '🥳', '👋']

function insertEmoji(emoji: string) {
  wrap(emoji, '')
  showEmoji.value = false
}

// Standard composer formatting shortcuts: Ctrl/Cmd+B (bold), +I (italic), +K (link).
function handleKeydown(event: KeyboardEvent) {
  if (!(event.ctrlKey || event.metaKey) || event.altKey || event.shiftKey) return
  switch (event.key.toLowerCase()) {
    case 'b':
      event.preventDefault()
      wrap('**', '**')
      break
    case 'i':
      event.preventDefault()
      wrap('*', '*')
      break
    case 'k':
      event.preventDefault()
      wrap('[', '](https://)')
      break
  }
}

async function preview() {
  if (!props.modelValue.trim()) return
  previewLoading.value = true
  try {
    const token = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content
    const res = await fetch(routes.forumPreview, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': token || '', Accept: 'application/json' },
      body: JSON.stringify({ body: props.modelValue }),
      credentials: 'same-origin',
    })
    const data = await res.json()
    previewHtml.value = data.html
  } finally {
    previewLoading.value = false
  }
}
</script>

<template>
  <div class="space-y-2">
    <div class="flex flex-wrap gap-1">
      <Button type="button" variant="outline" size="sm" @click="wrap('**', '**')">{{ t('components.markdownEditor.bold') }}</Button>
      <Button type="button" variant="outline" size="sm" @click="wrap('*', '*')">{{ t('components.markdownEditor.italic') }}</Button>
      <Button type="button" variant="outline" size="sm" @click="wrap('`', '`')">{{ t('components.markdownEditor.code') }}</Button>
      <Button type="button" variant="outline" size="sm" @click="wrap('[', '](https://)')">{{ t('components.markdownEditor.link') }}</Button>
      <Button type="button" variant="outline" size="sm" @click="wrap('~~', '~~')">{{ t('components.markdownEditor.strikethrough') }}</Button>
      <Button type="button" variant="outline" size="sm" @click="wrap('||', '||')">{{ t('components.markdownEditor.spoiler') }}</Button>
      <Button type="button" variant="outline" size="sm" @click="wrap('> ', '')">{{ t('components.markdownEditor.quote') }}</Button>
      <Button type="button" variant="outline" size="sm" @click="wrap('## ', '')">{{ t('components.markdownEditor.heading') }}</Button>
      <Button type="button" variant="outline" size="sm" @click="wrap('- ', '')">{{ t('components.markdownEditor.bulletList') }}</Button>
      <Button type="button" variant="outline" size="sm" @click="showEmoji = !showEmoji">{{ t('components.markdownEditor.emoji') }}</Button>
      <ImageUploadButton v-if="showImageUpload && canUploadImages" @insert="insertImage" />
      <p v-else-if="showImageUpload && !canUploadImages" class="text-xs text-muted-foreground">{{ t('components.markdownEditor.uploadLevelHint') }}</p>
      <Button type="button" variant="outline" size="sm" :disabled="previewLoading || !modelValue" @click="preview">
        {{ previewLoading ? t('components.markdownEditor.previewing') : t('components.markdownEditor.preview') }}
      </Button>
    </div>
    <div v-if="showEmoji" class="flex flex-wrap gap-1 rounded-md border p-2">
      <button
        v-for="e in emojis"
        :key="e"
        type="button"
        class="rounded px-1 text-lg hover:bg-muted"
        @click="insertEmoji(e)"
      >{{ e }}</button>
    </div>
    <p v-if="uploadingImage" class="text-xs text-muted-foreground">{{ t('components.imageUpload.uploading') }}</p>
    <MentionAutocomplete v-if="showMention" :model-value="modelValue" @update:model-value="update">
      <template #default="{ onInput }">
        <textarea
          :value="modelValue"
          :rows="rows"
          :placeholder="placeholder"
          :required="required"
          class="flex min-h-[80px] w-full rounded-md border border-input bg-transparent px-3 py-2 text-sm shadow-sm placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
          ref="textareaEl"
          @input="onInput"
          @keydown="handleKeydown"
          @paste="handlePaste"
          @drop="handleDrop"
          @dragover="handleDragOver"
        />
      </template>
    </MentionAutocomplete>
    <textarea
      v-else
      :value="modelValue"
      :rows="rows"
      :placeholder="placeholder"
      :required="required"
      class="flex min-h-[80px] w-full rounded-md border border-input bg-transparent px-3 py-2 text-sm shadow-sm placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
      ref="textareaEl"
      @input="update(($event.target as HTMLTextAreaElement).value)"
      @keydown="handleKeydown"
      @paste="handlePaste"
      @drop="handleDrop"
      @dragover="handleDragOver"
    />
    <div v-if="previewHtml" class="prose prose-sm max-w-none rounded-md border p-3 text-sm dark:prose-invert" v-html="previewHtml" />
  </div>
</template>
