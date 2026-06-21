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
import BlockEditor, { type BlockItem } from '@/components/admin/website/BlockEditor.vue'
import SeoFields from '@/components/admin/website/SeoFields.vue'
import TranslationsPanel from '@/components/admin/website/TranslationsPanel.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  title: string
  page: {
    title: string
    slug: string
    page_type: string
    status: string
    website_theme_id: number | null
    scheduled_at: string | null
    seo: Record<string, string>
    translations: Record<string, Record<string, string>>
  }
  blocks: BlockItem[]
  pageTypeOptions: Array<{ value: string; label: string }>
  statusOptions: Array<{ value: string; label: string }>
  themeOptions: Array<{ value: number; label: string }>
  locales: string[]
  submitUrl: string
  publishUrl: string | null
  scheduleUrl: string | null
  blocksBaseUrl: string | null
  revisionsUrl: string | null
  method: 'post' | 'patch'
  backUrl: string
  form_errors?: Record<string, string[]>
  canPublish?: boolean
}>()

const tab = ref<'basic' | 'blocks' | 'seo' | 'i18n'>('basic')
const scheduleAt = ref(props.page.scheduled_at || '')

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

function publishNow() {
  if (!props.publishUrl) return
  router.post(props.publishUrl)
}

function schedulePublish() {
  if (!props.scheduleUrl || !scheduleAt.value) return
  router.post(props.scheduleUrl, { publish_at: scheduleAt.value })
}
</script>

<template>
  <PageHeader :title="title" />

  <div class="mb-4 flex flex-wrap gap-2">
    <Button type="button" size="sm" :variant="tab === 'basic' ? 'default' : 'outline'" @click="tab = 'basic'">{{ t('admin.website.tabs.basic', 'Basic') }}</Button>
    <Button v-if="blocksBaseUrl" type="button" size="sm" :variant="tab === 'blocks' ? 'default' : 'outline'" @click="tab = 'blocks'">{{ t('admin.website.tabs.blocks', 'Blocks') }}</Button>
    <Button type="button" size="sm" :variant="tab === 'seo' ? 'default' : 'outline'" @click="tab = 'seo'">SEO</Button>
    <Button type="button" size="sm" :variant="tab === 'i18n' ? 'default' : 'outline'" @click="tab = 'i18n'">{{ t('admin.website.tabs.translations', 'Translations') }}</Button>
    <Button v-if="revisionsUrl" as-child size="sm" variant="outline">
      <Link :href="revisionsUrl">{{ t('admin.website.revisions.title', 'Revisions') }}</Link>
    </Button>
  </div>

  <form v-show="tab === 'basic'" class="max-w-lg space-y-4" @submit.prevent="submit">
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
        <option v-for="option in pageTypeOptions" :key="option.value" :value="option.value">{{ option.label }}</option>
      </Select>
    </div>
    <div class="space-y-2">
      <Label for="status">{{ t('admin.common.status') }}</Label>
      <Select id="status" v-model="form.page.status">
        <option v-for="option in statusOptions" :key="option.value" :value="option.value">{{ option.label }}</option>
      </Select>
    </div>
    <div v-if="themeOptions.length" class="space-y-2">
      <Label for="theme">{{ t('admin.website.theme', 'Theme') }}</Label>
      <Select id="theme" v-model="form.page.website_theme_id">
        <option :value="null">—</option>
        <option v-for="option in themeOptions" :key="option.value" :value="option.value">{{ option.label }}</option>
      </Select>
    </div>
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

  <div v-if="tab === 'blocks' && blocksBaseUrl" class="max-w-3xl">
    <BlockEditor :blocks="blocks" :base-url="blocksBaseUrl" />
  </div>

  <form v-show="tab === 'seo'" class="max-w-lg space-y-4" @submit.prevent="submit">
    <SeoFields v-model:seo="form.page.seo" />
    <Button type="submit" :disabled="form.processing">{{ t('admin.ui.save') }}</Button>
  </form>

  <form v-show="tab === 'i18n'" class="max-w-lg space-y-4" @submit.prevent="submit">
    <TranslationsPanel v-model:translations="form.page.translations" :locales="locales" :fields="['title']" />
    <Button type="submit" :disabled="form.processing">{{ t('admin.ui.save') }}</Button>
  </form>
</template>
