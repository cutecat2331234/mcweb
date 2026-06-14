<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'

defineOptions({ layout: AdminLayout })

const props = defineProps<{
  title: string
  category: { id?: number; name: string; slug: string; position: number; color_hex?: string; icon?: string }
  submitUrl: string
  method: 'post' | 'patch'
  backUrl: string
}>()

const form = useForm({ category: { ...props.category } })

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
      <Input id="name" v-model="form.category.name" required />
    </div>
    <div class="space-y-2">
      <Label for="slug">标识 (slug)</Label>
      <Input id="slug" v-model="form.category.slug" required />
    </div>
    <div class="space-y-2">
      <Label for="position">排序</Label>
      <Input id="position" v-model.number="form.category.position" type="number" min="0" />
    </div>
    <div class="space-y-2">
      <Label for="color_hex">颜色 (#hex)</Label>
      <Input id="color_hex" v-model="form.category.color_hex" placeholder="#2563eb" />
    </div>
    <div class="space-y-2">
      <Label for="icon">图标 (emoji)</Label>
      <Input id="icon" v-model="form.category.icon" placeholder="💬" />
    </div>
    <div class="flex gap-2">
      <Button type="submit" :disabled="form.processing">保存</Button>
      <Button as-child variant="outline">
        <Link :href="backUrl">取消</Link>
      </Button>
    </div>
  </form>
</template>
