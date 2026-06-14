<script setup lang="ts">
import { Link, router, useForm } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Textarea from '@/components/ui/Textarea.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const props = defineProps<{
  draft: {
    id: string
    title: string
    body: string
    tags: string
    section: { name: string; slug: string }
  }
}>()

const form = useForm({
  draft: {
    title: props.draft.title,
    body: props.draft.body,
    tags: props.draft.tags,
  },
})

function save() {
  form.patch(`/forum/drafts/${props.draft.id}`)
}

function publish() {
  router.post(`/forum/drafts/${props.draft.id}/publish`)
}

function destroy() {
  if (!confirm('确定删除此草稿？')) return
  router.delete(`/forum/drafts/${props.draft.id}`)
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
    <div class="space-y-2">
      <Label for="body">内容</Label>
      <Textarea id="body" v-model="form.draft.body" rows="10" placeholder="支持 **粗体**、*斜体*、`代码`、@用户名" />
    </div>
    <div class="space-y-2">
      <Label for="tags">标签（逗号分隔）</Label>
      <Input id="tags" v-model="form.draft.tags" />
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
