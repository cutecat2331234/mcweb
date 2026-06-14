<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Textarea from '@/components/ui/Textarea.vue'

defineOptions({ layout: AdminLayout })

const props = defineProps<{
  title: string
  section: {
    id?: number
    name: string
    slug: string
    description: string
    position: number
    forum_category_id: number | null
    parent_id: number | null
    create_topic_roles: string
    reply_roles: string
  }
  categories: Array<{ id: number; name: string }>
  parentSections: Array<{ id: number; name: string }>
  submitUrl: string
  method: 'post' | 'patch'
  backUrl: string
}>()

const form = useForm({ section: { ...props.section } })

function submit() {
  if (props.method === 'patch') {
    form.patch(props.submitUrl)
  } else {
    form.post(props.submitUrl)
  }
}
</script>

<template>
  <PageHeader :title="title" />

  <form class="max-w-lg space-y-4" @submit.prevent="submit">
    <div class="space-y-2">
      <Label for="name">名称</Label>
      <Input id="name" v-model="form.section.name" required />
    </div>
    <div class="space-y-2">
      <Label for="slug">标识 (slug)</Label>
      <Input id="slug" v-model="form.section.slug" required />
    </div>
    <div class="space-y-2">
      <Label for="description">描述</Label>
      <Textarea id="description" v-model="form.section.description" rows="3" />
    </div>
    <div class="space-y-2">
      <Label for="position">排序</Label>
      <Input id="position" v-model.number="form.section.position" type="number" min="0" />
    </div>
    <div class="space-y-2">
      <Label for="category">分类</Label>
      <select id="category" v-model="form.section.forum_category_id" class="h-9 w-full rounded-md border px-2 text-sm">
        <option :value="null">无分类</option>
        <option v-for="cat in categories" :key="cat.id" :value="cat.id">{{ cat.name }}</option>
      </select>
    </div>
    <div class="space-y-2">
      <Label for="parent">父级板块（可选）</Label>
      <select id="parent" v-model="form.section.parent_id" class="h-9 w-full rounded-md border px-2 text-sm">
        <option :value="null">无（顶级板块）</option>
        <option v-for="sec in parentSections" :key="sec.id" :value="sec.id">{{ sec.name }}</option>
      </select>
    </div>
    <div class="space-y-2">
      <Label for="create_topic_roles">发帖权限（角色 key，逗号分隔，空=所有人）</Label>
      <Input id="create_topic_roles" v-model="form.section.create_topic_roles" placeholder="例如：forum.member" />
    </div>
    <div class="space-y-2">
      <Label for="reply_roles">回复权限（角色 key，逗号分隔，空=所有人）</Label>
      <Input id="reply_roles" v-model="form.section.reply_roles" placeholder="例如：forum.member" />
    </div>
    <div class="flex gap-2">
      <Button type="submit" :disabled="form.processing">保存</Button>
      <Button as-child variant="outline">
        <Link :href="backUrl">取消</Link>
      </Button>
    </div>
  </form>
</template>
