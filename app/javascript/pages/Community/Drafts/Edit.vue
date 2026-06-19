<script setup lang="ts">
import { ref, computed } from 'vue'
import { Link, router, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Textarea from '@/components/ui/Textarea.vue'
import MarkdownEditor from '@/components/portal/MarkdownEditor.vue'
import TagGroupPicker from '@/components/portal/TagGroupPicker.vue'
import Select from '@/components/ui/Select.vue'
import Checkbox from '@/components/ui/Checkbox.vue'
import { routes } from '@/lib/routes'
import { confirm } from '@/lib/useConfirm'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

const props = defineProps<{
  draft: {
    id: string
    title: string
    body: string
    tags: string
    prefix?: string | null
    scheduled_at_input?: string | null
    section: { name: string; slug: string; prefixes?: string[]; tag_groups?: Array<{ name: string; slug: string; color_hex?: string | null; one_per_topic: boolean; required?: boolean; tags: Array<{ name: string; slug: string; color_hex?: string | null }> }> }
    poll?: {
      question: string
      options: string
      closes_days: number | string
      multiple_choice: boolean
      max_choices: number
      hide_results_until_vote: boolean
    } | null
  }
  warningRestrictions?: { post?: string | null; link?: string | null; pm?: string | null }
}>()

const showPoll = ref(!!props.draft.poll)
const tagPickerRef = ref<InstanceType<typeof TagGroupPicker> | null>(null)
const tagGroupError = ref('')
const linkError = ref('')

function containsLink(text: string) {
  return /https?:\/\/|www\./i.test(text)
}

const form = useForm({
  draft: {
    title: props.draft.title,
    body: props.draft.body,
    tags: props.draft.tags,
    prefix: props.draft.prefix || '',
    scheduled_at: props.draft.scheduled_at_input || '',
    clear_schedule: false,
    poll_question: props.draft.poll?.question || '',
    poll_options: props.draft.poll?.options || '',
    poll_closes_days: props.draft.poll?.closes_days?.toString() || '',
    poll_multiple_choice: props.draft.poll?.multiple_choice || false,
    poll_max_choices: props.draft.poll?.max_choices || 2,
    poll_hide_results_until_vote: props.draft.poll?.hide_results_until_vote || false,
  },
})

const prefixOptions = computed(() => [
  { value: '', label: t('forum.topics.noPrefix') },
  ...(props.draft.section.prefixes || []).map((p) => ({ value: p, label: p })),
])

function missingRequiredGroups(tags: string) {
  const names = tags.split(',').map((t) => t.trim()).filter(Boolean)
  return (props.draft.section.tag_groups || []).filter((group) => {
    if (!group.required) return false
    const groupNames = new Set(group.tags.map((t) => t.name))
    return !names.some((name) => groupNames.has(name))
  })
}

const tagsReady = computed(() => missingRequiredGroups(form.draft.tags).length === 0)

const bodyHasBlockedLink = computed(() =>
  !!(props.warningRestrictions?.link && containsLink(form.draft.body))
)

const canPublish = computed(() => tagsReady.value && !props.warningRestrictions?.post && !bodyHasBlockedLink.value)

function tagsValid() {
  if (!tagsReady.value) {
    tagGroupError.value = t('forum.topics.requiredTagsDraft')
    return false
  }
  tagGroupError.value = ''
  return true
}

function save() {
  if (!tagsValid()) return
  if (!showPoll.value) {
    form.draft.poll_question = ''
    form.draft.poll_options = ''
  }
  form.patch(`/app/forum/drafts/${props.draft.id}`)
}

function publish() {
  if (!tagsValid()) return
  if (props.warningRestrictions?.post) return
  if (props.warningRestrictions?.link && containsLink(form.draft.body)) {
    linkError.value = props.warningRestrictions.link
    return
  }
  router.post(`${routes.app}/forum/drafts/${props.draft.id}/publish`)
}

async function destroy() {
  const ok = await confirm({
    title: t('forum.drafts.deleteTitle'),
    message: t('forum.drafts.deleteConfirm'),
    confirmLabel: t('forum.drafts.delete'),
    variant: 'destructive',
  })
  if (!ok) return
  router.delete(`${routes.app}/forum/drafts/${props.draft.id}`)
}

function clearSchedule() {
  form.draft.clear_schedule = true
  form.draft.scheduled_at = ''
  save()
}
</script>

<template>
  <Breadcrumb :items="[
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.forum'), href: routes.forum },
    { label: t('forum.drafts.breadcrumb'), href: routes.forumDrafts },
    { label: draft.title, current: true },
  ]" />

  <PageHeader :title="t('forum.drafts.editTitle')" :subtitle="draft.section.name" />

  <p v-if="warningRestrictions?.post" class="mb-4 max-w-lg rounded-md border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900 dark:border-amber-800 dark:bg-amber-950 dark:text-amber-100">
    {{ warningRestrictions.post }}
  </p>

  <form class="max-w-lg space-y-4" @submit.prevent="save">
    <div class="space-y-2">
      <Label for="title">{{ t('forum.drafts.titleLabel') }}</Label>
      <Input id="title" v-model="form.draft.title" required />
    </div>
    <div v-if="draft.section.prefixes?.length" class="space-y-2">
      <Label for="prefix">{{ t('forum.drafts.prefixLabel') }}</Label>
      <Select id="prefix" v-model="form.draft.prefix" :options="prefixOptions" block />
    </div>
    <div class="space-y-2">
      <Label for="body">{{ t('forum.drafts.bodyLabel') }}</Label>
      <MarkdownEditor v-model="form.draft.body" :rows="10" :placeholder="t('forum.drafts.bodyPlaceholder')" />
      <p v-if="linkError" class="text-sm text-destructive">{{ linkError }}</p>
      <p v-else-if="bodyHasBlockedLink" class="text-sm text-destructive">{{ warningRestrictions?.link }}</p>
      <p v-else-if="warningRestrictions?.link" class="text-xs text-muted-foreground">{{ warningRestrictions.link }}</p>
    </div>
    <div class="space-y-2">
      <Label for="tags">{{ t('forum.topics.tagsLabel') }}</Label>
      <TagGroupPicker ref="tagPickerRef" v-model="form.draft.tags" :tag-groups="draft.section.tag_groups" :max-tags="5" />
      <p v-if="tagGroupError" class="text-sm text-destructive">{{ tagGroupError }}</p>
    </div>

    <div class="space-y-2">
      <Button type="button" variant="outline" size="sm" @click="showPoll = !showPoll">
        {{ showPoll ? t('forum.topics.hidePoll') : t('forum.drafts.editPoll') }}
      </Button>
      <div v-if="showPoll" class="space-y-2 rounded-lg border p-3">
        <Label for="poll_question">{{ t('forum.topics.pollQuestion') }}</Label>
        <Input id="poll_question" v-model="form.draft.poll_question" :placeholder="t('forum.topics.pollQuestionPlaceholder')" />
        <Label for="poll_options">{{ t('forum.drafts.pollOptionsRows') }}</Label>
        <Textarea id="poll_options" v-model="form.draft.poll_options" rows="4" />
        <Label for="poll_closes_days">{{ t('forum.drafts.pollClosesDays') }}</Label>
        <Input id="poll_closes_days" v-model="form.draft.poll_closes_days" type="number" min="0" />
        <label class="flex items-center gap-2 text-sm">
          <Checkbox v-model="form.draft.poll_multiple_choice" />
          {{ t('forum.topics.pollMultipleChoice') }}
        </label>
        <div v-if="form.draft.poll_multiple_choice" class="space-y-2">
          <Label for="poll_max_choices">{{ t('forum.topics.pollMaxChoices') }}</Label>
          <Input id="poll_max_choices" v-model.number="form.draft.poll_max_choices" type="number" min="2" max="10" />
        </div>
        <label class="flex items-center gap-2 text-sm">
          <Checkbox v-model="form.draft.poll_hide_results_until_vote" />
          {{ t('forum.topics.pollHideResults') }}
        </label>
      </div>
    </div>

    <div class="space-y-2">
      <Label for="scheduled_at">{{ t('forum.topics.scheduledPublish') }}</Label>
      <Input id="scheduled_at" v-model="form.draft.scheduled_at" type="datetime-local" />
      <p class="text-xs text-muted-foreground">{{ t('forum.drafts.scheduledHintEdit') }}</p>
      <Button v-if="draft.scheduled_at_input" type="button" variant="outline" size="sm" @click="clearSchedule">{{ t('forum.drafts.clearSchedule') }}</Button>
    </div>
    <div class="flex flex-wrap gap-2">
      <Button type="submit" :disabled="form.processing || !tagsReady">{{ t('forum.topics.saveDraft') }}</Button>
      <Button type="button" :disabled="!form.draft.body || !canPublish" @click="publish">{{ t('forum.drafts.publishTopic') }}</Button>
      <Button type="button" variant="destructive" @click="destroy">{{ t('forum.drafts.delete') }}</Button>
      <Button as-child variant="outline">
        <Link :href="routes.forumDrafts">{{ t('forum.drafts.back') }}</Link>
      </Button>
    </div>
  </form>
</template>
