<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Select from '@/components/ui/Select.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  title: string
  page: {
    title: string
    slug: string
    page_type: string
    status: string
  }
  pageTypeOptions: Array<{ value: string; label: string }>
  statusOptions: Array<{ value: string; label: string }>
  submitUrl: string
  method: 'post' | 'patch'
  backUrl: string
  form_errors?: Record<string, string[]>
}>()

const form = useForm({
  page: { ...props.page },
})

function fieldError(key: string) {
  return props.form_errors?.[key]?.join(' ') || form.errors[`page.${key}` as keyof typeof form.errors] || ''
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
      <Input id="title" v-model="form.page.title" required />
      <p v-if="fieldError('title')" class="text-sm text-destructive">{{ fieldError('title') }}</p>
    </div>
    <div class="space-y-2">
      <Label for="slug">{{ t('admin.forms.category.slug') }}</Label>
      <Input id="slug" v-model="form.page.slug" required />
      <p v-if="fieldError('slug')" class="text-sm text-destructive">{{ fieldError('slug') }}</p>
    </div>
    <div class="space-y-2">
      <Label for="page_type">{{ t('admin.website.pageType') }}</Label>
      <Select id="page_type" v-model="form.page.page_type">
        <option v-for="option in pageTypeOptions" :key="option.value" :value="option.value">
          {{ option.label }}
        </option>
      </Select>
    </div>
    <div class="space-y-2">
      <Label for="status">{{ t('admin.common.status') }}</Label>
      <Select id="status" v-model="form.page.status">
        <option v-for="option in statusOptions" :key="option.value" :value="option.value">
          {{ option.label }}
        </option>
      </Select>
    </div>
    <div class="flex gap-2">
      <Button type="submit" :disabled="form.processing">{{ t('admin.ui.save') }}</Button>
      <Button as-child variant="outline">
        <Link :href="backUrl">{{ t('admin.ui.cancel') }}</Link>
      </Button>
    </div>
  </form>
</template>
