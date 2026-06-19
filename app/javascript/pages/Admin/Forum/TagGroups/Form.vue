<script setup lang="ts">
import { ref } from 'vue'
import { Link, useForm } from '@inertiajs/vue3'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Checkbox from '@/components/ui/Checkbox.vue'
import Textarea from '@/components/ui/Textarea.vue'

defineOptions({ layout: AdminLayout })

const props = defineProps<{
  title: string
  tagGroup: {
    id?: number
    name: string
    slug: string
    description: string
    one_per_topic: boolean
    color_hex?: string
    tag_ids: number[]
  }
  tags: Array<{ id: number; name: string }>
  submitUrl: string
  method: 'post' | 'patch'
  backUrl: string
}>()

const selectedTagIds = ref<number[]>([...props.tagGroup.tag_ids])

const form = useForm({
  tag_group: {
    name: props.tagGroup.name,
    slug: props.tagGroup.slug,
    description: props.tagGroup.description,
    one_per_topic: props.tagGroup.one_per_topic,
    color_hex: props.tagGroup.color_hex || '',
    tag_ids: selectedTagIds.value,
  },
})

function toggleTag(id: number, checked: boolean) {
  if (checked) {
    if (!selectedTagIds.value.includes(id)) selectedTagIds.value.push(id)
  } else {
    const idx = selectedTagIds.value.indexOf(id)
    if (idx >= 0) selectedTagIds.value.splice(idx, 1)
  }
  form.tag_group.tag_ids = [...selectedTagIds.value]
}

function submit() {
  form.tag_group.tag_ids = [...selectedTagIds.value]
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
      <Input id="name" v-model="form.tag_group.name" required />
    </div>
    <div class="space-y-2">
      <Label for="slug">标识</Label>
      <Input id="slug" v-model="form.tag_group.slug" />
    </div>
    <div class="space-y-2">
      <Label for="description">描述</Label>
      <Textarea id="description" v-model="form.tag_group.description" rows="3" />
    </div>
    <div class="space-y-2">
      <Label for="color_hex">组颜色（Hex，可选）</Label>
      <Input id="color_hex" v-model="form.tag_group.color_hex" placeholder="#6366f1" />
    </div>
    <label class="flex items-center gap-2 text-sm">
      <Checkbox v-model="form.tag_group.one_per_topic" />
      每个主题只能从此组选一个标签（XenForo）
    </label>
    <div class="space-y-2">
      <Label>组内标签</Label>
      <div class="max-h-48 space-y-1 overflow-y-auto rounded-md border p-3">
        <label v-for="tag in tags" :key="tag.id" class="flex items-center gap-2 text-sm">
          <Checkbox
            :model-value="selectedTagIds.includes(tag.id)"
            @update:model-value="(checked) => toggleTag(tag.id, checked)"
          />
          {{ tag.name }}
        </label>
      </div>
    </div>
    <div class="flex gap-2">
      <Button type="submit" :disabled="form.processing">保存</Button>
      <Button as-child variant="outline">
        <Link :href="backUrl">返回</Link>
      </Button>
    </div>
  </form>
</template>
