<script setup lang="ts">
import { ref } from 'vue'
import { Link, router, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Select from '@/components/ui/Select.vue'
import Textarea from '@/components/ui/Textarea.vue'
import MarkdownEditor from '@/components/portal/MarkdownEditor.vue'
import SeoFields from '@/components/admin/website/SeoFields.vue'
import TranslationsPanel from '@/components/admin/website/TranslationsPanel.vue'

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
    body: string | null
    published_at: string | null
    scheduled_at: string | null
    seo: Record<string, string>
    translations: Record<string, Record<string, string>>
  }
  articleTypeOptions: Array<{ value: string; label: string }>
  statusOptions: Array<{ value: string; label: string }>
  locales: string[]
  submitUrl: string
  publishUrl: string | null
  scheduleUrl: string | null
  method: 'post' | 'patch'
  backUrl: string
  form_errors?: Record<string, string[]>
  canPublish?: boolean
}>()

const tab = ref<'basic' | 'body' | 'seo' | 'i18n'>('basic')
const scheduleAt = ref(props.article.scheduled_at || '')

const form = useForm({
  article: { ...props.article },
})

function fieldError(key: string) {
  return props.form_errors?.[key]?.join(' ') || form.errors[`article.${key}` as keyof typeof form.errors] || ''
}

function submit() {
  if (props.method === 'patch') form.patch(props.submitUrl)
  else form.post(props.submitUrl)
}

function publishNow() {
  if (props.publishUrl) router.post(props.publishUrl)
}

function schedulePublish() {
  if (props.scheduleUrl && scheduleAt.value) {
    router.post(props.scheduleUrl, { publish_at: scheduleAt.value })
  }
}
</script>

<template>
  <PageHeader :title="title" />

  <div class="mb-4 flex flex-wrap gap-2">
    <Button type="button" size="sm" :variant="tab === 'basic' ? 'default' : 'outline'" @click="tab = 'basic'">{{ t('admin.website.tabs.basic', 'Basic') }}</Button>
    <Button type="button" size="sm" :variant="tab === 'body' ? 'default' : 'outline'" @click="tab = 'body'">{{ t('admin.website.tabs.body', 'Body') }}</Button>
    <Button type="button" size="sm" :variant="tab === 'seo' ? 'default' : 'outline'" @click="tab = 'seo'">SEO</Button>
    <Button type="button" size="sm" :variant="tab === 'i18n' ? 'default' : 'outline'" @click="tab = 'i18n'">{{ t('admin.website.tabs.translations', 'Translations') }}</Button>
  </div>

  <form v-show="tab === 'basic'" class="max-w-lg space-y-4" @submit.prevent="submit">
    <div class="space-y-2"><Label for="title">{{ t('admin.common.title') }}</Label><Input id="title" v-model="form.article.title" required /></div>
    <div class="space-y-2"><Label for="slug">{{ t('admin.forms.category.slug') }}</Label><Input id="slug" v-model="form.article.slug" required /></div>
    <div class="space-y-2">
      <Label for="article_type">{{ t('admin.website.articleType') }}</Label>
      <Select id="article_type" v-model="form.article.article_type">
        <option v-for="option in articleTypeOptions" :key="option.value" :value="option.value">{{ option.label }}</option>
      </Select>
    </div>
    <div class="space-y-2">
      <Label>{{ t('admin.common.status') }}</Label>
      <p class="text-sm text-muted-foreground">{{ form.article.status }}</p>
    </div>
    <div class="space-y-2"><Label for="summary">{{ t('admin.website.summary') }}</Label><Textarea id="summary" v-model="form.article.summary" rows="3" /></div>
    <div v-if="canPublish && publishUrl" class="flex flex-wrap gap-2 border-t pt-4">
      <Button type="button" @click="publishNow">{{ t('admin.website.publish', 'Publish now') }}</Button>
      <Input v-model="scheduleAt" type="datetime-local" class="w-auto" />
      <Button type="button" variant="outline" @click="schedulePublish">{{ t('admin.website.schedule', 'Schedule') }}</Button>
    </div>
    <div class="flex gap-2">
      <Button type="submit" :disabled="form.processing">{{ t('admin.ui.save') }}</Button>
      <Button as-child variant="outline"><Link :href="backUrl">{{ t('admin.ui.cancel') }}</Link></Button>
    </div>
  </form>

  <form v-show="tab === 'body'" class="max-w-3xl space-y-4" @submit.prevent="submit">
    <MarkdownEditor v-model="form.article.body" :rows="16" />
    <Button type="submit" :disabled="form.processing">{{ t('admin.ui.save') }}</Button>
  </form>

  <form v-show="tab === 'seo'" class="max-w-lg space-y-4" @submit.prevent="submit">
    <SeoFields v-model:seo="form.article.seo" />
    <Button type="submit" :disabled="form.processing">{{ t('admin.ui.save') }}</Button>
  </form>

  <form v-show="tab === 'i18n'" class="max-w-lg space-y-4" @submit.prevent="submit">
    <TranslationsPanel v-model:translations="form.article.translations" :locales="locales" :fields="['title', 'summary']" />
    <Button type="submit" :disabled="form.processing">{{ t('admin.ui.save') }}</Button>
  </form>
</template>
