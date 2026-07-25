<script setup lang="ts">
import { computed, nextTick, ref } from 'vue'
import { usePage } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import { Message } from '@mcweb/ui'
import { IconEye, IconFaceSmileFill, IconImage } from '@arco-design/web-vue/es/icon'
import { routes } from '@/lib/routes'
import { csrfHeaders } from '@/lib/csrf'

const props = withDefaults(
  defineProps<{
    modelValue: string | null
    rows?: number
    placeholder?: string
    required?: boolean
    showImageUpload?: boolean
  }>(),
  {
    rows: 8,
    showImageUpload: true,
  },
)

const emit = defineEmits<{
  'update:modelValue': [value: string]
}>()

const { t } = useI18n()
const page = usePage()
const textareaComponent = ref<{ $el?: HTMLElement } | null>(null)
const previewHtml = ref<string | null>(null)
const previewLoading = ref(false)
const uploadingImage = ref(false)
const showEmoji = ref(false)
const emojiQuery = ref('')

const value = computed({
  get: () => props.modelValue || '',
  set: (nextValue: string) => emit('update:modelValue', nextValue),
})

const canUploadImages = computed(() => {
  const user = (page.props.auth as { user?: { can_upload_images?: boolean } } | undefined)?.user
  return user?.can_upload_images === true
})

const emojiCatalog = [
  { emoji: '😀', keywords: 'grin smile happy' },
  { emoji: '😂', keywords: 'laugh tears joy' },
  { emoji: '😍', keywords: 'love heart eyes' },
  { emoji: '😎', keywords: 'cool sunglasses' },
  { emoji: '🤔', keywords: 'thinking' },
  { emoji: '😭', keywords: 'cry sad' },
  { emoji: '😡', keywords: 'angry rage' },
  { emoji: '🎉', keywords: 'party celebrate' },
  { emoji: '🙏', keywords: 'thanks please' },
  { emoji: '👍', keywords: 'thumbs up yes' },
  { emoji: '👎', keywords: 'thumbs down no' },
  { emoji: '👏', keywords: 'clap applause' },
  { emoji: '❤️', keywords: 'heart love' },
  { emoji: '🔥', keywords: 'fire hot' },
  { emoji: '✨', keywords: 'sparkles shine' },
  { emoji: '✅', keywords: 'check done yes' },
  { emoji: '❌', keywords: 'cross no' },
  { emoji: '⚠️', keywords: 'warning caution' },
  { emoji: '🚀', keywords: 'rocket launch' },
  { emoji: '⭐', keywords: 'star favorite' },
  { emoji: '💡', keywords: 'idea light' },
  { emoji: '🐛', keywords: 'bug' },
  { emoji: '🎮', keywords: 'game' },
  { emoji: '⛏️', keywords: 'pickaxe mine minecraft' },
]

const filteredEmojis = computed(() => {
  const query = emojiQuery.value.trim().toLowerCase()
  return emojiCatalog.filter((item) => !query || item.keywords.includes(query))
})

function textareaElement() {
  return textareaComponent.value?.$el?.querySelector('textarea') ?? null
}

function restoreSelection(element: HTMLTextAreaElement, start: number, end: number) {
  nextTick(() => {
    element.focus()
    element.setSelectionRange(start, end)
  })
}

function wrap(before: string, after: string) {
  const currentValue = value.value
  const element = textareaElement()
  if (!element) {
    value.value = `${currentValue}${before}${after}`
    return
  }

  const start = element.selectionStart ?? currentValue.length
  const end = element.selectionEnd ?? currentValue.length
  const selected = currentValue.slice(start, end)
  value.value =
    currentValue.slice(0, start) + before + selected + after + currentValue.slice(end)
  restoreSelection(element, start + before.length, start + before.length + selected.length)
}

function insertText(text: string) {
  const currentValue = value.value
  const element = textareaElement()
  if (!element) {
    value.value = `${currentValue}${currentValue ? '\n' : ''}${text}`
    return
  }

  const start = element.selectionStart ?? currentValue.length
  const end = element.selectionEnd ?? currentValue.length
  value.value = currentValue.slice(0, start) + text + currentValue.slice(end)
  restoreSelection(element, start + text.length, start + text.length)
}

function insertEmoji(emoji: string) {
  insertText(emoji)
  showEmoji.value = false
  emojiQuery.value = ''
}

async function uploadImage(file: File) {
  if (!canUploadImages.value || uploadingImage.value) return false
  uploadingImage.value = true
  try {
    const body = new FormData()
    body.append('file', file)
    const response = await fetch(routes.forumUpload, {
      method: 'POST',
      headers: { ...csrfHeaders(), Accept: 'application/json' },
      body,
      credentials: 'same-origin',
    })
    const data = await response.json()
    if (response.ok && typeof data.markdown === 'string') {
      insertText(data.markdown)
    } else {
      Message.error(data.error || t('components.imageUpload.uploadFailed'))
    }
  } catch {
    Message.error(t('components.imageUpload.uploadFailed'))
  } finally {
    uploadingImage.value = false
  }
  return false
}

function handlePaste(event: ClipboardEvent) {
  if (!canUploadImages.value) return
  for (const item of Array.from(event.clipboardData?.items ?? [])) {
    if (item.kind !== 'file' || !item.type.startsWith('image/')) continue
    const file = item.getAsFile()
    if (!file) continue
    event.preventDefault()
    void uploadImage(file)
    return
  }
}

function handleDrop(event: DragEvent) {
  if (!canUploadImages.value) return
  const image = Array.from(event.dataTransfer?.files ?? []).find((file) =>
    file.type.startsWith('image/'),
  )
  if (!image) return
  event.preventDefault()
  void uploadImage(image)
}

function handleDragOver(event: DragEvent) {
  if (canUploadImages.value && Array.from(event.dataTransfer?.types ?? []).includes('Files')) {
    event.preventDefault()
  }
}

function handleKeydown(event: KeyboardEvent) {
  if (!(event.ctrlKey || event.metaKey) || event.altKey || event.shiftKey) return
  if (event.key.toLowerCase() === 'b') {
    event.preventDefault()
    wrap('**', '**')
  } else if (event.key.toLowerCase() === 'i') {
    event.preventDefault()
    wrap('*', '*')
  } else if (event.key.toLowerCase() === 'k') {
    event.preventDefault()
    wrap('[', '](https://)')
  }
}

async function preview() {
  if (!value.value.trim()) return
  previewLoading.value = true
  try {
    const response = await fetch(routes.forumPreview, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...csrfHeaders(),
        Accept: 'application/json',
      },
      body: JSON.stringify({ body: value.value }),
      credentials: 'same-origin',
    })
    const data = await response.json()
    if (response.ok && typeof data.html === 'string') {
      previewHtml.value = data.html
    } else {
      Message.error(data.error || t('components.markdownEditor.previewFailed', 'Preview failed'))
    }
  } catch {
    Message.error(t('components.markdownEditor.previewFailed', 'Preview failed'))
  } finally {
    previewLoading.value = false
  }
}
</script>

<template>
  <a-space direction="vertical" fill>
    <a-space wrap>
      <a-button size="small" @click="wrap('**', '**')">{{ t('components.markdownEditor.bold') }}</a-button>
      <a-button size="small" @click="wrap('*', '*')">{{ t('components.markdownEditor.italic') }}</a-button>
      <a-button size="small" @click="wrap('`', '`')">{{ t('components.markdownEditor.code') }}</a-button>
      <a-button size="small" @click="wrap('[', '](https://)')">{{ t('components.markdownEditor.link') }}</a-button>
      <a-button size="small" @click="wrap('~~', '~~')">{{ t('components.markdownEditor.strikethrough') }}</a-button>
      <a-button size="small" @click="wrap('> ', '')">{{ t('components.markdownEditor.quote') }}</a-button>
      <a-button size="small" @click="wrap('## ', '')">{{ t('components.markdownEditor.heading') }}</a-button>
      <a-button size="small" @click="wrap('- ', '')">{{ t('components.markdownEditor.bulletList') }}</a-button>
      <a-button size="small" @click="wrap('\n```\n', '\n```\n')">
        {{ t('components.markdownEditor.codeBlock') }}
      </a-button>
      <a-button size="small" @click="showEmoji = !showEmoji">
        <template #icon><icon-face-smile-fill /></template>
        {{ t('components.markdownEditor.emoji') }}
      </a-button>
      <a-upload
        v-if="showImageUpload && canUploadImages"
        accept="image/*"
        :auto-upload="false"
        :show-file-list="false"
        :disabled="uploadingImage"
        :before-upload="uploadImage"
      >
        <template #upload-button>
          <a-button size="small" :loading="uploadingImage">
            <template #icon><icon-image /></template>
            {{ t('components.imageUpload.insertImage') }}
          </a-button>
        </template>
      </a-upload>
      <a-button
        size="small"
        :loading="previewLoading"
        :disabled="!value"
        @click="preview"
      >
        <template #icon><icon-eye /></template>
        {{ t('components.markdownEditor.preview') }}
      </a-button>
    </a-space>

    <a-card v-if="showEmoji" :bordered="true" size="small">
      <a-input
        v-model="emojiQuery"
        :placeholder="t('components.markdownEditor.emojiSearch')"
        allow-clear
        class="mb-2"
      />
      <a-space wrap>
        <a-button
          v-for="item in filteredEmojis"
          :key="item.emoji"
          type="text"
          size="small"
          :aria-label="item.keywords"
          @click="insertEmoji(item.emoji)"
        >
          {{ item.emoji }}
        </a-button>
      </a-space>
      <a-empty
        v-if="!filteredEmojis.length"
        :description="t('components.markdownEditor.emojiNoResults')"
      />
    </a-card>

    <a-textarea
      ref="textareaComponent"
      v-model="value"
      :placeholder="placeholder"
      :auto-size="{ minRows: rows, maxRows: Math.max(rows * 2, rows + 4) }"
      :textarea-attrs="{ required }"
      @keydown="handleKeydown"
      @paste="handlePaste"
      @drop="handleDrop"
      @dragover="handleDragOver"
    />

    <a-card v-if="previewHtml" :title="t('components.markdownEditor.preview')" :bordered="true">
      <template #extra>
        <a-button type="text" size="small" @click="previewHtml = null">
          {{ t('common.close') }}
        </a-button>
      </template>
      <div class="admin-markdown-preview" v-html="previewHtml" />
    </a-card>
  </a-space>
</template>

<style scoped>
.admin-markdown-preview {
  overflow-wrap: anywhere;
  color: var(--color-text-1);
}

.admin-markdown-preview :deep(img) {
  max-width: 100%;
  height: auto;
}
</style>
