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
import MentionAutocomplete from '@/components/portal/MentionAutocomplete.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const props = defineProps<{
  section: { name: string; slug: string; url: string; prefixes?: string[] }
}>()

const form = useForm({
  topic: {
    title: '',
    body: '',
    tags: '',
    prefix: '',
    poll_question: '',
    poll_options: '',
    poll_closes_days: '',
  },
})

const previewHtml = ref<string | null>(null)
const previewLoading = ref(false)
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
    },
  })
}

async function preview() {
  if (!form.topic.body.trim()) return
  previewLoading.value = true
  try {
    const token = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content
    const res = await fetch(routes.forumPreview, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': token || '',
        Accept: 'application/json',
      },
      body: JSON.stringify({ body: form.topic.body }),
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
      <p v-if="form.errors.title" class="text-sm text-destructive">{{ form.errors.title }}</p>
    </div>
    <div v-if="section.prefixes?.length" class="space-y-2">
      <Label for="prefix">主题前缀</Label>
      <select id="prefix" v-model="form.topic.prefix" class="h-9 w-full rounded-md border px-2 text-sm">
        <option value="">无前缀</option>
        <option v-for="p in section.prefixes" :key="p" :value="p">{{ p }}</option>
      </select>
    </div>
    <div class="space-y-2">
      <Label for="body">首帖内容</Label>
      <MentionAutocomplete v-model="form.topic.body">
        <template #default="{ onInput }">
          <Textarea
            id="body"
            v-model="form.topic.body"
            required
            rows="8"
            placeholder="支持 **粗体**、*斜体*、`代码`、@用户名"
            @input="onInput"
          />
        </template>
      </MentionAutocomplete>
      <p v-if="form.errors.body" class="text-sm text-destructive">{{ form.errors.body }}</p>
      <div class="flex gap-2">
        <Button type="button" variant="outline" size="sm" :disabled="previewLoading || !form.topic.body" @click="preview">
          {{ previewLoading ? '预览中…' : '预览' }}
        </Button>
      </div>
      <div v-if="previewHtml" class="prose prose-sm max-w-none rounded-md border p-3 text-sm dark:prose-invert" v-html="previewHtml" />
    </div>
    <div class="space-y-2">
      <Label for="tags">标签（逗号分隔，最多 5 个）</Label>
      <Input id="tags" v-model="form.topic.tags" placeholder="例如：公告,活动" />
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
      </div>
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
