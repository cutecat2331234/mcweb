<script setup lang="ts">
import { ref, computed } from 'vue'
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
  return user?.can_upload_images !== false
})

function update(value: string) {
  emit('update:modelValue', value)
}

function wrap(before: string, after: string) {
  const value = props.modelValue
  emit('update:modelValue', `${value}${before}${after}`)
}

function insertImage(markdown: string) {
  const value = props.modelValue
  emit('update:modelValue', `${value}${value ? '\n\n' : ''}${markdown}`)
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
      <ImageUploadButton v-if="showImageUpload && canUploadImages" @insert="insertImage" />
      <p v-else-if="showImageUpload && !canUploadImages" class="text-xs text-muted-foreground">{{ t('components.markdownEditor.uploadLevelHint') }}</p>
      <Button type="button" variant="outline" size="sm" :disabled="previewLoading || !modelValue" @click="preview">
        {{ previewLoading ? t('components.markdownEditor.previewing') : t('components.markdownEditor.preview') }}
      </Button>
    </div>
    <MentionAutocomplete v-if="showMention" :model-value="modelValue" @update:model-value="update">
      <template #default="{ onInput }">
        <textarea
          :value="modelValue"
          :rows="rows"
          :placeholder="placeholder"
          :required="required"
          class="flex min-h-[80px] w-full rounded-md border border-input bg-transparent px-3 py-2 text-sm shadow-sm placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
          @input="onInput"
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
      @input="update(($event.target as HTMLTextAreaElement).value)"
    />
    <div v-if="previewHtml" class="prose prose-sm max-w-none rounded-md border p-3 text-sm dark:prose-invert" v-html="previewHtml" />
  </div>
</template>
