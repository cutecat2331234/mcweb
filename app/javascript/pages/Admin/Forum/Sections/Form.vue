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
    prefixes: string
    create_topic_roles: string
    reply_roles: string
    required_tag_ids: number[]
    allowed_tag_ids: number[]
    prefix_required: boolean
    topic_template: string
  }
  tags: Array<{ id: number; name: string }>
  categories: Array<{ id: number; name: string }>
  parentSections: Array<{ id: number; name: string }>
  submitUrl: string
  method: 'post' | 'patch'
  backUrl: string
}>()

const form = useForm({
  section: {
    ...props.section,
    required_tag_ids: [ ...props.section.required_tag_ids ],
    allowed_tag_ids: [ ...props.section.allowed_tag_ids ],
  },
})

function toggleRequiredTag(tagId: number) {
  const ids = form.section.required_tag_ids
  const index = ids.indexOf(tagId)
  if (index >= 0) {
    ids.splice(index, 1)
  } else {
    ids.push(tagId)
  }
}

function toggleAllowedTag(tagId: number) {
  const ids = form.section.allowed_tag_ids
  const index = ids.indexOf(tagId)
  if (index >= 0) {
    ids.splice(index, 1)
  } else {
    ids.push(tagId)
  }
}

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
      <Label for="create_topic_roles">发帖权限（权限 key，逗号分隔，空=所有人）</Label>
      <Input id="create_topic_roles" v-model="form.section.create_topic_roles" placeholder="例如：forum.topics.lock" />
    </div>
    <div class="space-y-2">
      <Label for="reply_roles">回复权限（权限 key，逗号分隔，空=所有人）</Label>
      <Input id="reply_roles" v-model="form.section.reply_roles" placeholder="例如：forum.topics.lock" />
    </div>
    <div class="space-y-2">
      <Label for="prefixes">主题前缀（每行一个，如：公告、求助）</Label>
      <Textarea id="prefixes" v-model="form.section.prefixes" rows="3" placeholder="公告&#10;求助&#10;分享" />
      <label class="flex items-center gap-2 text-sm">
        <input v-model="form.section.prefix_required" type="checkbox" class="h-4 w-4" />
        发帖时必须选择前缀
      </label>
    </div>
    <div class="space-y-2">
      <Label for="topic_template">主题模板（XenForo，发帖时预填正文）</Label>
      <Textarea id="topic_template" v-model="form.section.topic_template" rows="5" placeholder="请按以下格式填写…" />
    </div>
    <div v-if="tags.length" class="space-y-2">
      <Label>必填标签（发帖时至少选一个，XenForo 风格）</Label>
      <div class="max-h-40 space-y-2 overflow-y-auto rounded-md border p-3">
        <label v-for="tag in tags" :key="tag.id" class="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            class="h-4 w-4"
            :checked="form.section.required_tag_ids.includes(tag.id)"
            @change="toggleRequiredTag(tag.id)"
          />
          {{ tag.name }}
        </label>
      </div>
      <p class="text-xs text-muted-foreground">勾选后，用户在此分区发帖必须包含至少一个所选标签。</p>
    </div>
    <div v-if="tags.length" class="space-y-2">
      <Label>允许标签（白名单，空=不限制）</Label>
      <div class="max-h-40 space-y-2 overflow-y-auto rounded-md border p-3">
        <label v-for="tag in tags" :key="`allowed-${tag.id}`" class="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            class="h-4 w-4"
            :checked="form.section.allowed_tag_ids.includes(tag.id)"
            @change="toggleAllowedTag(tag.id)"
          />
          {{ tag.name }}
        </label>
      </div>
      <p class="text-xs text-muted-foreground">勾选后，仅可使用列表中的标签；留空表示不限制。</p>
    </div>
    <div class="flex gap-2">
      <Button type="submit" :disabled="form.processing">保存</Button>
      <Button as-child variant="outline">
        <Link :href="backUrl">取消</Link>
      </Button>
    </div>
  </form>
</template>
