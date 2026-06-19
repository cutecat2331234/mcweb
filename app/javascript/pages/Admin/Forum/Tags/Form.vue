<script setup lang="ts">
import { computed } from 'vue'
import { Link, useForm } from '@inertiajs/vue3'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Select from '@/components/ui/Select.vue'
import Checkbox from '@/components/ui/Checkbox.vue'
import Textarea from '@/components/ui/Textarea.vue'

defineOptions({ layout: AdminLayout })

const props = defineProps<{
  title: string
  tag: { id?: number; name: string; slug: string; description: string; staff_only: boolean; color_hex: string; canonical_tag_id?: number | null }
  canonicalTags?: Array<{ id: number; name: string }>
  submitUrl: string
  method: 'post' | 'patch'
  backUrl: string
}>()

const form = useForm({ tag: { ...props.tag } })

const canonicalTagOptions = computed(() => [
  { value: '', label: '无（独立标签）' },
  ...(props.canonicalTags || []).map((tag) => ({ value: String(tag.id), label: tag.name })),
])

function updateCanonicalTagId(value: string) {
  form.tag.canonical_tag_id = value ? Number(value) : null
}

function submit() {
  if (props.method === 'patch') form.patch(props.submitUrl)
  else form.post(props.submitUrl)
}
</script>

<template>
  <PageHeader :title="title" />
  <form class="max-w-lg space-y-4" @submit.prevent="submit">
    <div class="space-y-2">
      <Label for="name">名称</Label>
      <Input id="name" v-model="form.tag.name" required />
    </div>
    <div class="space-y-2">
      <Label for="slug">标识</Label>
      <Input id="slug" v-model="form.tag.slug" required />
    </div>
    <div class="space-y-2">
      <Label for="description">描述</Label>
      <Textarea id="description" v-model="form.tag.description" rows="3" />
    </div>
    <div class="space-y-2">
      <Label for="color_hex">颜色（Hex）</Label>
      <Input id="color_hex" v-model="form.tag.color_hex" placeholder="#22c55e" />
    </div>
    <div v-if="canonicalTags?.length" class="space-y-2">
      <Label for="canonical_tag_id">同义词指向（可选）</Label>
      <Select
        id="canonical_tag_id"
        :model-value="form.tag.canonical_tag_id == null ? '' : String(form.tag.canonical_tag_id)"
        :options="canonicalTagOptions"
        block
        @update:model-value="updateCanonicalTagId"
      />
      <p class="text-xs text-muted-foreground">设为某标签的同义词后，发帖与搜索将归并到主标签。</p>
    </div>
    <label class="flex items-center gap-2 text-sm">
      <Checkbox v-model="form.tag.staff_only" />
      仅工作人员可使用
    </label>
    <div class="flex gap-2">
      <Button type="submit" :disabled="form.processing">保存</Button>
      <Button as-child variant="outline"><Link :href="backUrl">返回</Link></Button>
    </div>
  </form>
</template>
