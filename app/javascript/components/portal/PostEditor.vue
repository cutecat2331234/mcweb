<script setup lang="ts">
// Composer host that offers a WYSIWYG <-> Markdown source toggle.
//
// Both modes operate on the SAME v-model (markdown body), so content is
// preserved losslessly across toggles and the stored value remains compatible
// with the server's FormatPostBody markdown->HTML pipeline.
//
//  - Markdown mode  -> existing MarkdownEditor.vue (textarea + toolbar, emoji,
//                      mentions/hashtags, image upload, server preview). Kept as
//                      the safe default + fallback.
//  - WYSIWYG mode   -> RichTextEditor.vue (TipTap), serializing to markdown.
//
// Default is Markdown to stay safe; users opt into WYSIWYG. The preference is
// remembered in localStorage so it sticks across composers/sessions.
import { ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import Button from '@/components/ui/Button.vue'
import MarkdownEditor from '@/components/portal/MarkdownEditor.vue'
import RichTextEditor from '@/components/portal/RichTextEditor.vue'

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

const { t } = useI18n()

const STORAGE_KEY = 'mcweb.composer.mode'
type Mode = 'markdown' | 'wysiwyg'

function readStoredMode(): Mode {
  try {
    return localStorage.getItem(STORAGE_KEY) === 'wysiwyg' ? 'wysiwyg' : 'markdown'
  } catch {
    return 'markdown'
  }
}

const mode = ref<Mode>(readStoredMode())

function setMode(next: Mode) {
  if (mode.value === next) return
  mode.value = next
  try {
    localStorage.setItem(STORAGE_KEY, next)
  } catch {
    /* localStorage may be unavailable (private mode); ignore. */
  }
}

watch(mode, () => {
  // Content lives in the shared v-model, so no transfer is needed on toggle —
  // each editor reads/writes the same markdown body.
})

function update(value: string) {
  emit('update:modelValue', value)
}
</script>

<template>
  <div class="space-y-2">
    <div class="flex items-center gap-1 text-xs">
      <span class="mr-1 text-muted-foreground">{{ t('components.postEditor.modeLabel') }}</span>
      <Button
        type="button"
        :variant="mode === 'markdown' ? 'default' : 'outline'"
        size="sm"
        :aria-pressed="mode === 'markdown'"
        @click="setMode('markdown')"
      >{{ t('components.postEditor.markdownMode') }}</Button>
      <Button
        type="button"
        :variant="mode === 'wysiwyg' ? 'default' : 'outline'"
        size="sm"
        :aria-pressed="mode === 'wysiwyg'"
        @click="setMode('wysiwyg')"
      >{{ t('components.postEditor.wysiwygMode') }}</Button>
    </div>

    <RichTextEditor
      v-if="mode === 'wysiwyg'"
      :model-value="modelValue"
      :placeholder="placeholder"
      :show-image-upload="showImageUpload"
      @update:model-value="update"
    />
    <MarkdownEditor
      v-else
      :model-value="modelValue"
      :rows="rows"
      :placeholder="placeholder"
      :required="required"
      :show-image-upload="showImageUpload"
      :show-mention="showMention"
      @update:model-value="update"
    />
    <p v-if="mode === 'wysiwyg'" class="text-xs text-muted-foreground">
      {{ t('components.postEditor.wysiwygHint') }}
    </p>
  </div>
</template>
