<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Textarea from '@/components/ui/Textarea.vue'
import { adminRoutes } from '@/lib/adminRoutes'

defineOptions({ layout: AdminLayout })

const props = defineProps<{
  title: string
  badge: {
    id?: number
    name: string
    slug: string
    description: string
    icon: string
    color: string
    grant_rule: string
    grant_threshold: number
  }
  submitUrl: string
  method: 'post' | 'patch'
  backUrl: string
}>()

const form = useForm({ badge: { ...props.badge } })

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
      <Input id="name" v-model="form.badge.name" required />
    </div>
    <div class="space-y-2">
      <Label for="slug">标识</Label>
      <Input id="slug" v-model="form.badge.slug" required />
    </div>
    <div class="space-y-2">
      <Label for="icon">图标（emoji）</Label>
      <Input id="icon" v-model="form.badge.icon" />
    </div>
    <div class="space-y-2">
      <Label for="color">颜色</Label>
      <Input id="color" v-model="form.badge.color" placeholder="#6366f1" />
    </div>
    <div class="space-y-2">
      <Label for="grant_rule">授予规则</Label>
      <select id="grant_rule" v-model="form.badge.grant_rule" class="h-9 w-full rounded-md border px-2 text-sm">
        <option value="manual">手动</option>
        <option value="first_topic">首帖</option>
        <option value="posts_count">发帖数</option>
        <option value="likes_received">获赞数</option>
      </select>
    </div>
    <div class="space-y-2">
      <Label for="grant_threshold">阈值（发帖/获赞规则）</Label>
      <Input id="grant_threshold" v-model.number="form.badge.grant_threshold" type="number" min="0" />
    </div>
    <div class="space-y-2">
      <Label for="description">描述</Label>
      <Textarea id="description" v-model="form.badge.description" rows="3" />
    </div>
    <div class="flex gap-2">
      <Button type="submit" :disabled="form.processing">保存</Button>
      <Button as-child variant="outline"><Link :href="backUrl">返回</Link></Button>
    </div>
  </form>
</template>
