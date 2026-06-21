<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Select from '@/components/ui/Select.vue'
import Textarea from '@/components/ui/Textarea.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  title: string
  article: {
    title: string
    slug: string
    article_type: string
    status: string
    summary: string | null
    published_at: string | null
  }
  articleTypeOptions: Array<{ value: string; label: string }>
  statusOptions: Array<{ value: string; label: string }>
  submitUrl: string
  method: 'post' | 'patch'
  backUrl: string
  form_errors?: Record<string, string[]>
}>()

const form = useForm({
  article: { ...props.article },
})

function fieldError(key: string) {
  return props.form_errors?.[key]?.join(' ') || form.errors[`article.${key}` as keyof typeof form.errors] || ''
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
      <Label for="title">{{ t('admin.common.title') }}</Label>
      <Input id="title" v-model="form.article.title" required />
      <p v-if="fieldError('title')" class="text-sm text-destructive">{{ fieldError('title') }}</p>
    </div>
    <div class="space-y-2">
      <Label for="slug">{{ t('admin.forms.category.slug') }}</Label>
      <Input id="slug" v-model="form.article.slug" required />
      <p v-if="fieldError('slug')" class="text-sm text-destructive">{{ fieldError('slug') }}</p>
    </div>
    <div class="space-y-2">
      <Label for="article_type">{{ t('admin.website.articleType') }}</Label>
      <Select id="article_type" v-model="form.article.article_type">
        <option v-for="option in articleTypeOptions" :key="option.value" :value="option.value">
          {{ option.label }}
        </option>
      </Select>
    </div>
    <div class="space-y-2">
      <Label for="status">{{ t('admin.common.status') }}</Label>
      <Select id="status" v-model="form.article.status">
        <option v-for="option in statusOptions" :key="option.value" :value="option.value">
          {{ option.label }}
        </option>
      </Select>
    </div>
    <div class="space-y-2">
      <Label for="summary">{{ t('admin.website.summary') }}</Label>
      <Textarea id="summary" v-model="form.article.summary" rows="3" />
    </div>
    <div class="space-y-2">
      <Label for="published_at">{{ t('admin.website.publishedAt') }}</Label>
      <Input id="published_at" v-model="form.article.published_at" type="datetime-local" />
    </div>
    <div class="flex gap-2">
      <Button type="submit" :disabled="form.processing">{{ t('admin.ui.save') }}</Button>
      <Button as-child variant="outline">
        <Link :href="backUrl">{{ t('admin.ui.cancel') }}</Link>
      </Button>
    </div>
  </form>
</template>
