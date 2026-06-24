<script setup lang="ts">
// WYSIWYG (what-you-see-is-what-you-get) editor built on TipTap / ProseMirror.
//
// OUTPUT COMPATIBILITY: the forum stores bodies as MARKDOWN, rendered by
// Community::FormatPostBody. To stay drop-in compatible, this editor edits
// visually but serializes the document back to that same markdown dialect on
// every change (see lib/richTextMarkdown.ts). The v-model value is therefore
// always markdown, identical in shape to what the textarea MarkdownEditor emits.
//
// Incoming markdown (e.g. an existing draft, or content switched over from the
// Markdown source view) is parsed to HTML and loaded into the editor.
import { ref, watch, onBeforeUnmount, computed } from 'vue'
import { usePage } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import { useEditor, EditorContent } from '@tiptap/vue-3'
import StarterKit from '@tiptap/starter-kit'
import { Link } from '@tiptap/extension-link'
import { Image } from '@tiptap/extension-image'
import Button from '@/components/ui/Button.vue'
import ImageUploadButton from '@/components/portal/ImageUploadButton.vue'
import { markdownToHtml, docToMarkdown } from '@/lib/richTextMarkdown'
import { routes } from '@/lib/routes'

const props = withDefaults(defineProps<{
  modelValue: string
  placeholder?: string
  showImageUpload?: boolean
}>(), {
  showImageUpload: true,
})

const emit = defineEmits<{
  'update:modelValue': [value: string]
}>()

const { t } = useI18n()
const page = usePage()
const canUploadImages = computed(() => {
  const user = (page.props.auth as { user?: { can_upload_images?: boolean } } | undefined)?.user
  return user?.can_upload_images === true
})

// Guard so that markdown we emit ourselves does not feed straight back in and
// reset the cursor / reparse on every keystroke.
let emitting = false

const editor = useEditor({
  content: markdownToHtml(props.modelValue || ''),
  extensions: [
    StarterKit.configure({
      // Link is configured separately below so we can control autolink/openOnClick.
      link: false,
    }),
    Link.configure({
      openOnClick: false,
      autolink: true,
      HTMLAttributes: { rel: 'nofollow noopener', target: '_blank' },
    }),
    Image.configure({ inline: false, allowBase64: false }),
  ],
  editorProps: {
    attributes: {
      class:
        'prose prose-sm max-w-none min-h-[160px] rounded-md border border-input bg-transparent px-3 py-2 text-sm focus:outline-none focus-visible:ring-2 focus-visible:ring-ring dark:prose-invert',
    },
  },
  onUpdate: ({ editor }) => {
    emitting = true
    emit('update:modelValue', docToMarkdown(editor.getJSON()))
  },
})

// External value change (parent reset, toggle from Markdown source, draft load):
// reparse markdown into the editor unless we are the source of the change.
watch(
  () => props.modelValue,
  (value) => {
    if (emitting) {
      emitting = false
      return
    }
    const current = docToMarkdown(editor.value?.getJSON())
    if (current === (value || '')) return
    editor.value?.commands.setContent(markdownToHtml(value || ''), { emitUpdate: false })
  },
)

onBeforeUnmount(() => editor.value?.destroy())

function setLink() {
  const previous = editor.value?.getAttributes('link').href as string | undefined
  const url = window.prompt(t('components.richTextEditor.linkPrompt'), previous || 'https://')
  if (url === null) return
  if (url === '') {
    editor.value?.chain().focus().extendMarkRange('link').unsetLink().run()
    return
  }
  editor.value?.chain().focus().extendMarkRange('link').setLink({ href: url }).run()
}

// Reuse the existing upload pipeline (forum/uploads). The endpoint returns
// markdown like ![alt](url); we parse out the URL and insert an image node.
function insertUploadedImage(markdown: string) {
  const match = markdown.match(/!\[([^\]]*)\]\(([^)\s]+)\)/)
  if (match) {
    editor.value?.chain().focus().setImage({ src: match[2], alt: match[1] }).run()
  } else {
    editor.value?.chain().focus().insertContent(markdown).run()
  }
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
    if (res.ok && data.markdown) insertUploadedImage(data.markdown)
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
  const images = Array.from(event.dataTransfer?.files ?? []).filter((f) => f.type.startsWith('image/'))
  if (images.length) {
    event.preventDefault()
    images.forEach((file) => uploadImageFile(file))
  }
}

function isActive(name: string, attrs?: Record<string, unknown>) {
  return editor.value?.isActive(name, attrs) ?? false
}
</script>

<template>
  <div class="space-y-2">
    <div v-if="editor" class="flex flex-wrap gap-1">
      <Button type="button" variant="outline" size="sm" :class="{ 'bg-muted': isActive('bold') }" @click="editor.chain().focus().toggleBold().run()">{{ t('components.markdownEditor.bold') }}</Button>
      <Button type="button" variant="outline" size="sm" :class="{ 'bg-muted': isActive('italic') }" @click="editor.chain().focus().toggleItalic().run()">{{ t('components.markdownEditor.italic') }}</Button>
      <Button type="button" variant="outline" size="sm" :class="{ 'bg-muted': isActive('strike') }" @click="editor.chain().focus().toggleStrike().run()">{{ t('components.markdownEditor.strikethrough') }}</Button>
      <Button type="button" variant="outline" size="sm" :class="{ 'bg-muted': isActive('code') }" @click="editor.chain().focus().toggleCode().run()">{{ t('components.markdownEditor.code') }}</Button>
      <Button type="button" variant="outline" size="sm" :class="{ 'bg-muted': isActive('link') }" @click="setLink">{{ t('components.markdownEditor.link') }}</Button>
      <Button type="button" variant="outline" size="sm" :class="{ 'bg-muted': isActive('heading', { level: 2 }) }" @click="editor.chain().focus().toggleHeading({ level: 2 }).run()">{{ t('components.markdownEditor.heading') }}</Button>
      <Button type="button" variant="outline" size="sm" :class="{ 'bg-muted': isActive('bulletList') }" @click="editor.chain().focus().toggleBulletList().run()">{{ t('components.markdownEditor.bulletList') }}</Button>
      <Button type="button" variant="outline" size="sm" :class="{ 'bg-muted': isActive('orderedList') }" @click="editor.chain().focus().toggleOrderedList().run()">{{ t('components.richTextEditor.orderedList') }}</Button>
      <Button type="button" variant="outline" size="sm" :class="{ 'bg-muted': isActive('blockquote') }" @click="editor.chain().focus().toggleBlockquote().run()">{{ t('components.markdownEditor.quote') }}</Button>
      <Button type="button" variant="outline" size="sm" :class="{ 'bg-muted': isActive('codeBlock') }" @click="editor.chain().focus().toggleCodeBlock().run()">{{ t('components.markdownEditor.codeBlock') }}</Button>
      <Button type="button" variant="outline" size="sm" @click="editor.chain().focus().setHorizontalRule().run()">{{ t('components.markdownEditor.horizontalRule') }}</Button>
      <ImageUploadButton v-if="showImageUpload && canUploadImages" @insert="insertUploadedImage" />
      <p v-else-if="showImageUpload && !canUploadImages" class="text-xs text-muted-foreground">{{ t('components.markdownEditor.uploadLevelHint') }}</p>
    </div>
    <EditorContent
      :editor="editor"
      :data-placeholder="placeholder"
      @paste="handlePaste"
      @drop="handleDrop"
    />
    <p v-if="uploadingImage" class="text-xs text-muted-foreground">{{ t('components.imageUpload.uploading') }}</p>
  </div>
</template>
