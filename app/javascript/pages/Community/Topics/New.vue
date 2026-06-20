<script setup lang="ts">
import { ref, watch, computed } from 'vue'
import { Link, router, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Alert from '@/components/ui/Alert.vue'
import MarkdownEditor from '@/components/portal/MarkdownEditor.vue'
import AttachmentUploadButton, { type PendingAttachment } from '@/components/portal/AttachmentUploadButton.vue'
import TagGroupPicker from '@/components/portal/TagGroupPicker.vue'
import Textarea from '@/components/ui/Textarea.vue'
import Select from '@/components/ui/Select.vue'
import Checkbox from '@/components/ui/Checkbox.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

const props = defineProps<{
  section: { name: string; slug: string; url: string; prefixes?: string[]; prefix_required?: boolean; topic_template?: string | null; required_tags?: Array<{ name: string; slug: string; url: string }>; required_tag_groups?: Array<{ name: string; slug: string }>; tag_groups?: Array<{ name: string; slug: string; color_hex?: string | null; one_per_topic: boolean; required?: boolean; tags: Array<{ name: string; slug: string; color_hex?: string | null }> }>; allowed_tags?: Array<{ name: string; slug: string; url: string }>; default_tags?: string[] }
  similarTitlesUrl?: string
  warningRestrictions?: { post?: string | null; link?: string | null; pm?: string | null }
  form_errors?: Record<string, string>
}>()

const similarTitles = ref<Array<{ title: string; url: string }>>([])
const tagPickerRef = ref<InstanceType<typeof TagGroupPicker> | null>(null)
const tagGroupError = ref('')
const linkError = ref('')
let similarTimer: ReturnType<typeof setTimeout> | null = null

function containsLink(text: string) {
  return /https?:\/\/|www\./i.test(text)
}

function missingRequiredGroups(tags: string) {
  const names = tags.split(',').map((t) => t.trim()).filter(Boolean)
  return (props.section.tag_groups || []).filter((group) => {
    if (!group.required) return false
    const groupNames = new Set(group.tags.map((t) => t.name))
    return !names.some((name) => groupNames.has(name))
  })
}

const form = useForm({
  topic: {
    title: '',
    body: props.section.topic_template || '',
    tags: (props.section.default_tags || []).join(', '),
    prefix: '',
    poll_question: '',
    poll_options: '',
    poll_closes_days: '',
    poll_multiple_choice: false,
    poll_max_choices: 2,
    poll_hide_results_until_vote: false,
    scheduled_at: '',
    attachment_ids: [] as number[],
  },
})
const pendingAttachments = ref<PendingAttachment[]>([])

function onAttachmentUploaded(attachment: PendingAttachment) {
  pendingAttachments.value.push(attachment)
  form.topic.attachment_ids = pendingAttachments.value.map((item) => item.id)
}

function removePendingAttachment(id: number) {
  pendingAttachments.value = pendingAttachments.value.filter((item) => item.id !== id)
  form.topic.attachment_ids = pendingAttachments.value.map((item) => item.id)
}

watch(
  () => props.form_errors,
  (errors) => {
    if (!errors) return
    Object.entries(errors).forEach(([key, message]) => {
      form.setError(key as keyof typeof form.errors, message)
    })
  },
  { immediate: true },
)

const formError = computed(() => {
  if (form.errors.base) return form.errors.base
  return props.form_errors?.base || ''
})

function fieldError(key: string) {
  return form.errors[`topic.${key}` as keyof typeof form.errors] || props.form_errors?.[`topic.${key}`] || ''
}

const prefixOptions = computed(() => [
  ...(props.section.prefix_required ? [] : [{ value: '', label: t('forum.topics.noPrefix') }]),
  ...(props.section.prefixes || []).map((p) => {
    if (typeof p === 'string') return { value: p, label: p }
    return { value: p.name, label: p.label || p.name }
  }),
])

const tagsReady = computed(() => missingRequiredGroups(form.topic.tags).length === 0)
const bodyHasBlockedLink = computed(() =>
  !!(props.warningRestrictions?.link && containsLink(form.topic.body))
)
const canPublish = computed(() => tagsReady.value && !props.warningRestrictions?.post && !bodyHasBlockedLink.value)

function validateBeforeSubmit() {
  tagGroupError.value = ''
  linkError.value = ''
  if (!tagsReady.value) {
    tagGroupError.value = t('forum.topics.requiredTagsPublish')
    return false
  }
  if (props.warningRestrictions?.post) return false
  if (props.warningRestrictions?.link && containsLink(form.topic.body)) {
    linkError.value = props.warningRestrictions.link
    return false
  }
  return true
}

watch(() => form.topic.title, (title) => {
  if (!props.similarTitlesUrl || title.length < 3) {
    similarTitles.value = []
    return
  }
  if (similarTimer) clearTimeout(similarTimer)
  similarTimer = setTimeout(async () => {
    try {
      const response = await fetch(`${props.similarTitlesUrl}?title=${encodeURIComponent(title)}`, {
        headers: { Accept: 'application/json' },
        credentials: 'same-origin',
      })
      if (response.ok) {
        const data = await response.json()
        similarTitles.value = data.titles || []
      }
    } catch {
      similarTitles.value = []
    }
  }, 400)
})

watch(() => form.topic.body, (body) => {
  linkError.value =
    props.warningRestrictions?.link && containsLink(body)
      ? props.warningRestrictions.link
      : ''
})

const showPoll = ref(false)

function submit() {
  if (!validateBeforeSubmit()) return
  form.post(`${routes.app}/forum/topics?section_id=${props.section.slug}`)
}

function saveDraft() {
  if (!tagsReady.value) {
    tagGroupError.value = t('forum.topics.requiredTagsDraft')
    return
  }
  router.post(`${routes.app}/forum/drafts?section_id=${props.section.slug}`, {
    draft: {
      title: form.topic.title,
      body: form.topic.body,
      tags: form.topic.tags,
      prefix: form.topic.prefix,
      scheduled_at: form.topic.scheduled_at,
      poll_question: showPoll.value ? form.topic.poll_question : '',
      poll_options: showPoll.value ? form.topic.poll_options : '',
      poll_closes_days: showPoll.value ? form.topic.poll_closes_days : '',
      poll_multiple_choice: showPoll.value ? form.topic.poll_multiple_choice : false,
      poll_max_choices: form.topic.poll_max_choices,
      poll_hide_results_until_vote: showPoll.value ? form.topic.poll_hide_results_until_vote : false,
      attachment_ids: form.topic.attachment_ids,
    },
  })
}

</script>

<template>
  <Breadcrumb :items="[
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.forum'), href: routes.forum },
    { label: section.name, href: section.url },
    { label: t('forum.topics.newTopic'), current: true },
  ]" />

  <PageHeader :title="t('forum.topics.newTopic')" :subtitle="section.name" />

  <p v-if="warningRestrictions?.post" class="mb-4 rounded-md border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900 dark:border-amber-800 dark:bg-amber-950 dark:text-amber-100">
    {{ warningRestrictions.post }}
  </p>

  <Alert v-if="formError" variant="destructive" class="mb-4 max-w-lg">
    {{ formError }}
  </Alert>

  <form class="max-w-lg space-y-4" @submit.prevent="submit">
    <div class="space-y-2">
      <Label for="title">{{ t('forum.topics.topicTitle') }}</Label>
      <Input id="title" v-model="form.topic.title" required autofocus />
      <div v-if="similarTitles.length" class="rounded-md border border-amber-200 bg-amber-50 px-3 py-2 text-sm text-amber-900 dark:border-amber-800 dark:bg-amber-950 dark:text-amber-100">
        <p class="font-medium">{{ t('forum.topics.similarTopics') }}</p>
        <ul class="mt-1 list-inside list-disc">
          <li v-for="item in similarTitles" :key="item.url">
            <Link :href="item.url" class="underline" target="_blank">{{ item.title }}</Link>
          </li>
        </ul>
      </div>
      <p v-if="fieldError('title')" class="text-sm text-destructive">{{ fieldError('title') }}</p>
    </div>
    <div v-if="section.prefixes?.length" class="space-y-2">
      <Label for="prefix">{{ t('forum.topics.prefix') }}{{ section.prefix_required ? t('forum.topics.prefixRequired') : '' }}</Label>
      <Select id="prefix" v-model="form.topic.prefix" :options="prefixOptions" block />
    </div>
    <div class="space-y-2">
      <Label for="body">{{ t('forum.topics.firstPost') }}</Label>
      <MarkdownEditor v-model="form.topic.body" :rows="8" :placeholder="t('forum.topics.firstPostPlaceholder')" />
      <p v-if="linkError" class="text-sm text-destructive">{{ linkError }}</p>
      <p v-else-if="bodyHasBlockedLink" class="text-sm text-destructive">{{ warningRestrictions?.link }}</p>
      <p v-else-if="warningRestrictions?.link" class="text-xs text-muted-foreground">{{ warningRestrictions.link }}</p>
      <p v-if="fieldError('body')" class="text-sm text-destructive">{{ fieldError('body') }}</p>
    </div>
    <div class="space-y-2">
      <Label for="tags">{{ t('forum.topics.tagsLabel') }}</Label>
      <TagGroupPicker ref="tagPickerRef" v-model="form.topic.tags" :tag-groups="section.tag_groups" :max-tags="5" />
      <p v-if="tagGroupError" class="text-sm text-destructive">{{ tagGroupError }}</p>
      <p v-if="section.required_tags?.length" class="text-xs text-muted-foreground">
        {{ t('forum.topics.requiredTagsHint') }}
        <template v-for="(tag, index) in section.required_tags" :key="tag.slug">
          <Link :href="tag.url" class="underline">{{ tag.name }}</Link><span v-if="index < section.required_tags.length - 1">{{ t('common.listSeparator') }}</span>
        </template>
      </p>
      <p v-if="section.required_tag_groups?.length" class="text-xs text-muted-foreground">
        {{ t('forum.topics.requiredTagGroupsHint') }}
        {{ section.required_tag_groups.map((g) => g.name).join(t('common.listSeparator')) }}
      </p>
      <p v-if="section.allowed_tags?.length" class="text-xs text-muted-foreground">
        {{ t('forum.topics.allowedTagsHint') }}
        <template v-for="(tag, index) in section.allowed_tags" :key="`allowed-${tag.slug}`">
          <Link :href="tag.url" class="underline">{{ tag.name }}</Link><span v-if="index < section.allowed_tags.length - 1">{{ t('common.listSeparator') }}</span>
        </template>
      </p>
      <p v-if="section.default_tags?.length" class="text-xs text-muted-foreground">
        {{ t('forum.topics.defaultTagsLabel') }}{{ section.default_tags.join(t('common.listSeparator')) }}
      </p>
    </div>

    <div class="space-y-2">
      <Button type="button" variant="outline" size="sm" @click="showPoll = !showPoll">
        {{ showPoll ? t('forum.topics.hidePoll') : t('forum.topics.addPoll') }}
      </Button>
      <div v-if="showPoll" class="space-y-2 rounded-lg border p-3">
        <Label for="poll_question">{{ t('forum.topics.pollQuestion') }}</Label>
        <Input id="poll_question" v-model="form.topic.poll_question" :placeholder="t('forum.topics.pollQuestionPlaceholder')" />
        <Label for="poll_options">{{ t('forum.topics.pollOptions') }}</Label>
        <Textarea id="poll_options" v-model="form.topic.poll_options" rows="4" :placeholder="t('forum.topics.pollOptionsPlaceholder')" />
        <Label for="poll_closes_days">{{ t('forum.topics.pollCloseDays') }}</Label>
        <Input id="poll_closes_days" v-model="form.topic.poll_closes_days" type="number" min="0" placeholder="0" />
        <label class="flex items-center gap-2 text-sm">
          <Checkbox v-model="form.topic.poll_multiple_choice" />
          {{ t('forum.topics.pollMultipleChoice') }}
        </label>
        <div v-if="form.topic.poll_multiple_choice" class="space-y-2">
          <Label for="poll_max_choices">{{ t('forum.topics.pollMaxChoices') }}</Label>
          <Input id="poll_max_choices" v-model.number="form.topic.poll_max_choices" type="number" min="2" max="10" />
        </div>
        <label class="flex items-center gap-2 text-sm">
          <Checkbox v-model="form.topic.poll_hide_results_until_vote" />
          {{ t('forum.topics.pollHideResults') }}
        </label>
      </div>
    </div>

    <div class="space-y-2">
      <AttachmentUploadButton @uploaded="onAttachmentUploaded" />
      <ul v-if="pendingAttachments.length" class="space-y-1 text-sm">
        <li class="text-xs font-medium text-muted-foreground">{{ t('components.attachmentUpload.pending') }}</li>
        <li v-for="attachment in pendingAttachments" :key="attachment.id" class="flex items-center justify-between gap-2 rounded border px-2 py-1">
          <span>{{ attachment.filename }} <span class="text-muted-foreground">({{ attachment.human_size }})</span></span>
          <button type="button" class="text-xs text-destructive hover:underline" @click="removePendingAttachment(attachment.id)">
            {{ t('components.attachmentUpload.remove') }}
          </button>
        </li>
      </ul>
    </div>

    <div class="space-y-2">
      <Label for="scheduled_at">{{ t('forum.topics.scheduledPublish') }}</Label>
      <Input id="scheduled_at" v-model="form.topic.scheduled_at" type="datetime-local" />
      <p class="text-xs text-muted-foreground">{{ t('forum.topics.scheduledHint') }}</p>
    </div>

    <div class="flex flex-wrap gap-3">
      <Button type="submit" :disabled="form.processing || !canPublish">{{ t('forum.topics.publish') }}</Button>
      <Button type="button" variant="outline" :disabled="!form.topic.title || !tagsReady" @click="saveDraft">{{ t('forum.topics.saveDraft') }}</Button>
      <Button as-child variant="outline">
        <Link :href="section.url">{{ t('forum.topics.cancel') }}</Link>
      </Button>
    </div>
  </form>
</template>
