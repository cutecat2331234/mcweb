<script setup lang="ts">
import { ref } from 'vue'
import { Link, router, useForm } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Textarea from '@/components/ui/Textarea.vue'
import MarkdownEditor from '@/components/portal/MarkdownEditor.vue'
import TagGroupPicker from '@/components/portal/TagGroupPicker.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const props = defineProps<{
  draft: {
    id: string
    title: string
    body: string
    tags: string
    prefix?: string | null
    scheduled_at_input?: string | null
    section: { name: string; slug: string; prefixes?: string[]; tag_groups?: Array<{ name: string; slug: string; color_hex?: string | null; one_per_topic: boolean; tags: Array<{ name: string; slug: string; color_hex?: string | null }> }> }
    poll?: {
      question: string
      options: string
      closes_days: number | string
      multiple_choice: boolean
      max_choices: number
      hide_results_until_vote: boolean
    } | null
  }
}>()

const showPoll = ref(!!props.draft.poll)
const tagPickerRef = ref<InstanceType<typeof TagGroupPicker> | null>(null)
const tagGroupError = ref('')

function tagsValid() {
  if (tagPickerRef.value?.hasMissingRequired) {
    tagGroupError.value = '请从必填标签组中至少选择一个标签。'
    return false
  }
  tagGroupError.value = ''
  return true
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

function save() {
  if (!tagsValid()) return
  if (!showPoll.value) {
    form.draft.poll_question = ''
    form.draft.poll_options = ''
  }
  form.patch(`/forum/drafts/${props.draft.id}`)
}

function publish() {
  if (!tagsValid()) return
  router.post(`/forum/drafts/${props.draft.id}/publish`)
}

function destroy() {
  if (!confirm('确定删除此草稿？')) return
  router.delete(`/forum/drafts/${props.draft.id}`)
}

function clearSchedule() {
  form.draft.clear_schedule = true
  form.draft.scheduled_at = ''
  save()
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: '我的草稿', href: routes.forumDrafts },
    { label: draft.title, current: true },
  ]" />

  <PageHeader title="编辑草稿" :subtitle="draft.section.name" />

  <form class="max-w-lg space-y-4" @submit.prevent="save">
    <div class="space-y-2">
      <Label for="title">标题</Label>
      <Input id="title" v-model="form.draft.title" required />
    </div>
    <div v-if="draft.section.prefixes?.length" class="space-y-2">
      <Label for="prefix">主题前缀</Label>
      <select id="prefix" v-model="form.draft.prefix" class="h-9 w-full rounded-md border px-2 text-sm">
        <option value="">无前缀</option>
        <option v-for="p in draft.section.prefixes" :key="p" :value="p">{{ p }}</option>
      </select>
    </div>
    <div class="space-y-2">
      <Label for="body">内容</Label>
      <MarkdownEditor v-model="form.draft.body" :rows="10" placeholder="支持 **粗体**、*斜体*、`代码`、@用户名、[^脚注]" />
    </div>
    <div class="space-y-2">
      <Label for="tags">标签（最多 5 个）</Label>
      <TagGroupPicker ref="tagPickerRef" v-model="form.draft.tags" :tag-groups="draft.section.tag_groups" :max-tags="5" />
      <p v-if="tagGroupError" class="text-sm text-destructive">{{ tagGroupError }}</p>
    </div>

    <div class="space-y-2">
      <Button type="button" variant="outline" size="sm" @click="showPoll = !showPoll">
        {{ showPoll ? '隐藏投票' : '编辑投票' }}
      </Button>
      <div v-if="showPoll" class="space-y-2 rounded-lg border p-3">
        <Label for="poll_question">投票问题</Label>
        <Input id="poll_question" v-model="form.draft.poll_question" placeholder="你想问什么？" />
        <Label for="poll_options">选项（每行一个）</Label>
        <Textarea id="poll_options" v-model="form.draft.poll_options" rows="4" />
        <Label for="poll_closes_days">自动关闭（天数，0 表示不关闭）</Label>
        <Input id="poll_closes_days" v-model="form.draft.poll_closes_days" type="number" min="0" />
        <label class="flex items-center gap-2 text-sm">
          <input v-model="form.draft.poll_multiple_choice" type="checkbox" class="h-4 w-4" />
          允许多选投票
        </label>
        <div v-if="form.draft.poll_multiple_choice" class="space-y-2">
          <Label for="poll_max_choices">最多可选几项</Label>
          <Input id="poll_max_choices" v-model.number="form.draft.poll_max_choices" type="number" min="2" max="10" />
        </div>
        <label class="flex items-center gap-2 text-sm">
          <input v-model="form.draft.poll_hide_results_until_vote" type="checkbox" class="h-4 w-4" />
          投票后才显示结果
        </label>
      </div>
    </div>

    <div class="space-y-2">
      <Label for="scheduled_at">定时发布（可选）</Label>
      <Input id="scheduled_at" v-model="form.draft.scheduled_at" type="datetime-local" />
      <p class="text-xs text-muted-foreground">设置未来时间将在指定时刻自动发布。</p>
      <Button v-if="draft.scheduled_at_input" type="button" variant="outline" size="sm" @click="clearSchedule">取消定时</Button>
    </div>
    <div class="flex flex-wrap gap-2">
      <Button type="submit" :disabled="form.processing">保存草稿</Button>
      <Button type="button" :disabled="!form.draft.body" @click="publish">发布主题</Button>
      <Button type="button" variant="destructive" @click="destroy">删除</Button>
      <Button as-child variant="outline">
        <Link :href="routes.forumDrafts">返回</Link>
      </Button>
    </div>
  </form>
</template>
