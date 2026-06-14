<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const props = defineProps<{
  section: { name: string; slug: string; url: string }
}>()

const form = useForm({
  topic: { title: '' },
})

function submit() {
  form.post(`/forum/topics?section_id=${props.section.slug}`)
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
    <div class="flex gap-3">
      <Button type="submit" :disabled="form.processing">创建</Button>
      <Button as-child variant="outline">
        <Link :href="section.url">取消</Link>
      </Button>
    </div>
  </form>
</template>
