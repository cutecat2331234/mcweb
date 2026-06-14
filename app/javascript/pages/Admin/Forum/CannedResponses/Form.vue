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
  canned_response: { title: string; body: string }
  submitUrl: string
  method?: 'post' | 'patch'
  backUrl: string
  deleteUrl?: string | null
}>()

const form = useForm({ canned_response: { ...props.canned_response } })

function submit() {
  if (props.method === 'patch') {
    form.patch(props.submitUrl)
  } else {
    form.post(props.submitUrl)
  }
}

function destroy() {
  if (!props.deleteUrl || !confirm('确定删除此罐头回复？')) return
  form.delete(props.deleteUrl)
}
</script>

<template>
  <PageHeader :title="title" />

  <form class="max-w-lg space-y-4" @submit.prevent="submit">
    <div class="space-y-2">
      <Label for="title">标题</Label>
      <Input id="title" v-model="form.canned_response.title" required />
    </div>
    <div class="space-y-2">
      <Label for="body">正文</Label>
      <Textarea id="body" v-model="form.canned_response.body" rows="6" required />
    </div>
    <div class="flex gap-2">
      <Button type="submit" :disabled="form.processing">保存</Button>
      <Button v-if="deleteUrl" type="button" variant="destructive" @click="destroy">删除</Button>
      <Button as-child variant="outline">
        <Link :href="backUrl">返回</Link>
      </Button>
    </div>
  </form>
</template>
