<script setup lang="ts">
import { ref, watch } from 'vue'
import { Link, router, useForm } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import MarkdownEditor from '@/components/portal/MarkdownEditor.vue'
import TagGroupPicker from '@/components/portal/TagGroupPicker.vue'
import Textarea from '@/components/ui/Textarea.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const props = defineProps<{
  section: { name: string; slug: string; url: string; prefixes?: string[]; prefix_required?: boolean; topic_template?: string | null; required_tags?: Array<{ name: string; slug: string; url: string }>; required_tag_groups?: Array<{ name: string; slug: string }>; tag_groups?: Array<{ name: string; slug: string; color_hex?: string | null; one_per_topic: boolean; tags: Array<{ name: string; slug: string; color_hex?: string | null }> }>; allowed_tags?: Array<{ name: string; slug: string; url: string }>; default_tags?: string[] }
  similarTitlesUrl?: string
}>()

const similarTitles = ref<Array<{ title: string; url: string }>>([])
let similarTimer: ReturnType<typeof setTimeout> | null = null

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
  },
})

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

const showPoll = ref(false)

function submit() {
  form.post(`/forum/topics?section_id=${props.section.slug}`)
}

function saveDraft() {
  router.post(`/forum/drafts?section_id=${props.section.slug}`, {
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
    },
  })
}

</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: section.name, href: section.url },
    { label: '新建主题', current: true },
  ]" />

  <PageHeader title="新建主题" :subtitle="section.name" />

  <form class="max-w-lg space-y-4" @submit.prevent="submit">
    <div class="space-y-2">
      <Label for="title">标题</Label>
      <Input id="title" v-model="form.topic.title" required autofocus />
      <div v-if="similarTitles.length" class="rounded-md border border-amber-200 bg-amber-50 px-3 py-2 text-sm text-amber-900 dark:border-amber-800 dark:bg-amber-950 dark:text-amber-100">
        <p class="font-medium">发现相似主题（Discourse 风格提示）</p>
        <ul class="mt-1 list-inside list-disc">
          <li v-for="item in similarTitles" :key="item.url">
            <Link :href="item.url" class="underline" target="_blank">{{ item.title }}</Link>
          </li>
        </ul>
      </div>
      <p v-if="form.errors.title" class="text-sm text-destructive">{{ form.errors.title }}</p>
    </div>
    <div v-if="section.prefixes?.length" class="space-y-2">
      <Label for="prefix">主题前缀{{ section.prefix_required ? '（必选）' : '' }}</Label>
      <select id="prefix" v-model="form.topic.prefix" class="h-9 w-full rounded-md border px-2 text-sm" :required="section.prefix_required">
        <option v-if="!section.prefix_required" value="">无前缀</option>
        <option v-for="p in section.prefixes" :key="p" :value="p">{{ p }}</option>
      </select>
    </div>
    <div class="space-y-2">
      <Label for="body">首帖内容</Label>
      <MarkdownEditor v-model="form.topic.body" :rows="8" placeholder="支持 **粗体**、*斜体*、`代码`、@用户名" />
      <p v-if="form.errors.body" class="text-sm text-destructive">{{ form.errors.body }}</p>
    </div>
    <div class="space-y-2">
      <Label for="tags">标签（最多 5 个）</Label>
      <TagGroupPicker v-model="form.topic.tags" :tag-groups="section.tag_groups" :max-tags="5" />
      <p v-if="section.required_tags?.length" class="text-xs text-muted-foreground">
        此分区要求至少包含以下标签之一：
        <template v-for="(tag, index) in section.required_tags" :key="tag.slug">
          <Link :href="tag.url" class="underline">{{ tag.name }}</Link><span v-if="index < section.required_tags.length - 1">、</span>
        </template>
      </p>
      <p v-if="section.required_tag_groups?.length" class="text-xs text-muted-foreground">
        此分区要求从以下标签组中至少选一个标签：
        {{ section.required_tag_groups.map((g) => g.name).join('、') }}
      </p>
      <p v-if="section.allowed_tags?.length" class="text-xs text-muted-foreground">
        此分区仅允许使用：
        <template v-for="(tag, index) in section.allowed_tags" :key="`allowed-${tag.slug}`">
          <Link :href="tag.url" class="underline">{{ tag.name }}</Link><span v-if="index < section.allowed_tags.length - 1">、</span>
        </template>
      </p>
      <p v-if="section.default_tags?.length" class="text-xs text-muted-foreground">
        默认标签：{{ section.default_tags.join('、') }}
      </p>
    </div>

    <div class="space-y-2">
      <Button type="button" variant="outline" size="sm" @click="showPoll = !showPoll">
        {{ showPoll ? '隐藏投票' : '添加投票' }}
      </Button>
      <div v-if="showPoll" class="space-y-2 rounded-lg border p-3">
        <Label for="poll_question">投票问题</Label>
        <Input id="poll_question" v-model="form.topic.poll_question" placeholder="你想问什么？" />
        <Label for="poll_options">选项（每行一个，至少 2 个）</Label>
        <Textarea id="poll_options" v-model="form.topic.poll_options" rows="4" placeholder="选项 A&#10;选项 B&#10;选项 C" />
        <Label for="poll_closes_days">自动关闭（天数，0 表示不关闭）</Label>
        <Input id="poll_closes_days" v-model="form.topic.poll_closes_days" type="number" min="0" placeholder="0" />
        <label class="flex items-center gap-2 text-sm">
          <input v-model="form.topic.poll_multiple_choice" type="checkbox" class="h-4 w-4" />
          允许多选投票
        </label>
        <div v-if="form.topic.poll_multiple_choice" class="space-y-2">
          <Label for="poll_max_choices">最多可选几项</Label>
          <Input id="poll_max_choices" v-model.number="form.topic.poll_max_choices" type="number" min="2" max="10" />
        </div>
        <label class="flex items-center gap-2 text-sm">
          <input v-model="form.topic.poll_hide_results_until_vote" type="checkbox" class="h-4 w-4" />
          投票后才显示结果
        </label>
      </div>
    </div>

    <div class="space-y-2">
      <Label for="scheduled_at">定时发布（可选）</Label>
      <Input id="scheduled_at" v-model="form.topic.scheduled_at" type="datetime-local" />
      <p class="text-xs text-muted-foreground">留空则立即发布；设置未来时间将保存为定时草稿。</p>
    </div>

    <div class="flex flex-wrap gap-3">
      <Button type="submit" :disabled="form.processing">发布</Button>
      <Button type="button" variant="outline" :disabled="!form.topic.title" @click="saveDraft">保存草稿</Button>
      <Button as-child variant="outline">
        <Link :href="section.url">取消</Link>
      </Button>
    </div>
  </form>
</template>
