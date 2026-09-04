<script setup lang="ts">
import { ref } from 'vue'
import { router, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import { Modal } from '@mcweb/ui'
import AdminLayout from '@/layouts/AdminLayout.vue'
import BlockEditor, { type BlockItem } from '@/components/admin/website/BlockEditor.vue'
import SeoFields from '@/components/admin/website/SeoFields.vue'
import TranslationsPanel from '@/components/admin/website/TranslationsPanel.vue'
import { navigateFrontendDocument } from '@/lib/applicationNavigation'
import { createIdempotencyKey } from '@/lib/idempotency'
import { confirmUnsavedNavigation } from '@/lib/unsavedForms'

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
    lock_version: number
  }
  blocks: BlockItem[]
  pageTypeOptions: Array<{ value: string; label: string }>
  statusOptions: Array<{ value: string; label: string }>
  themeOptions: Array<{ value: number; label: string }>
  locales: string[]
  submitUrl: string
  publishUrl: string | null
  scheduleUrl: string | null
  previewUrl: string | null
  blocksBaseUrl: string | null
  revisionsUrl: string | null
  method: 'post' | 'patch'
  backUrl: string
  form_errors?: Record<string, string[]>
  canPublish?: boolean
}>()

const tab = ref<'basic' | 'blocks' | 'seo' | 'i18n'>('basic')
const scheduleAt = ref(props.page.scheduled_at || '')
const form = useForm({ page: { ...props.page }, request_id: createIdempotencyKey() })
const themeOptionsWithDefault = [
  { value: null, label: '—' },
  ...props.themeOptions,
]

function fieldError(key: string) {
  const inertiaError = form.errors[`page.${key}` as keyof typeof form.errors]
  return props.form_errors?.[key]?.join(' ') || (inertiaError ? String(inertiaError) : '')
}

function submit() {
  if (props.method === 'patch') form.patch(props.submitUrl)
  else form.post(props.submitUrl)
}

function publishNow() {
  if (!props.publishUrl) return
  Modal.warning({
    title: t('admin.website.publish', 'Publish now'),
    content: t('admin.website.publishPageConfirm', 'Publish this page now?'),
    okText: t('admin.website.publish', 'Publish now'),
    cancelText: t('admin.ui.cancel'),
    hideCancel: false,
    onOk: () => router.post(props.publishUrl!, {
      lock_version: props.page.lock_version,
      request_id: createIdempotencyKey(),
    }),
  })
}

function schedulePublish() {
  if (!props.scheduleUrl || !scheduleAt.value) return
  router.post(props.scheduleUrl, {
    publish_at: scheduleAt.value,
    lock_version: props.page.lock_version,
    request_id: createIdempotencyKey(),
  })
}

function openPreview() {
  if (!props.previewUrl || !confirmUnsavedNavigation()) return
  navigateFrontendDocument(props.previewUrl)
}
</script>

<template>
  <a-page-header :title="title" :show-back="false">
    <template #extra>
      <a-space wrap>
        <a-button v-if="previewUrl" @click="openPreview">
          {{ t('admin.website.preview') }}
        </a-button>
        <a-button v-if="revisionsUrl" @click="router.visit(revisionsUrl)">
          {{ t('admin.website.revisions.title', 'Revisions') }}
        </a-button>
        <a-button @click="router.visit(backUrl)">{{ t('admin.ui.cancel') }}</a-button>
      </a-space>
    </template>
  </a-page-header>

  <a-tabs v-model:active-key="tab" type="card-gutter">
    <a-tab-pane key="basic" :title="t('admin.website.tabs.basic', 'Basic')">
      <a-card :bordered="true" class="admin-form-card">
        <a-form :model="form.page" layout="vertical" @submit="submit">
          <a-form-item
            field="title"
            :label="t('admin.common.title')"
            required
            :validate-status="fieldError('title') ? 'error' : undefined"
            :help="fieldError('title')"
          >
            <a-input v-model="form.page.title" allow-clear />
          </a-form-item>
          <a-form-item
            field="slug"
            :label="t('admin.forms.category.slug')"
            required
            :validate-status="fieldError('slug') ? 'error' : undefined"
            :help="fieldError('slug')"
          >
            <a-input v-model="form.page.slug" allow-clear />
          </a-form-item>
          <a-form-item field="page_type" :label="t('admin.website.pageType')">
            <a-select v-model="form.page.page_type" :options="pageTypeOptions" />
          </a-form-item>
          <a-form-item :label="t('admin.common.status')">
            <a-tag>{{ statusOptions.find((option) => option.value === form.page.status)?.label || form.page.status }}</a-tag>
          </a-form-item>
          <a-form-item
            v-if="themeOptions.length"
            field="website_theme_id"
            :label="t('admin.website.theme', 'Theme')"
          >
            <a-select
              v-model="form.page.website_theme_id"
              :options="themeOptionsWithDefault"
              allow-clear
            />
          </a-form-item>

          <a-card
            v-if="canPublish && publishUrl"
            :title="t('admin.website.publish', 'Publish')"
            :bordered="true"
            class="mb-4"
          >
            <a-space wrap>
              <a-button type="primary" status="success" @click="publishNow">
                {{ t('admin.website.publish', 'Publish now') }}
              </a-button>
              <a-date-picker
                v-model="scheduleAt"
                show-time
                value-format="YYYY-MM-DDTHH:mm"
                style="width: 230px"
              />
              <a-button :disabled="!scheduleAt" @click="schedulePublish">
                {{ t('admin.website.schedule', 'Schedule') }}
              </a-button>
            </a-space>
          </a-card>

          <a-button html-type="submit" type="primary" :loading="form.processing">
            {{ t('admin.ui.save') }}
          </a-button>
        </a-form>
      </a-card>
    </a-tab-pane>

    <a-tab-pane
      v-if="blocksBaseUrl"
      key="blocks"
      :title="t('admin.website.tabs.blocks', 'Blocks')"
    >
      <BlockEditor
        :blocks="blocks"
        :base-url="blocksBaseUrl"
        :page-lock-version="page.lock_version"
      />
    </a-tab-pane>

    <a-tab-pane key="seo" title="SEO">
      <a-card :bordered="true" class="admin-form-card">
        <SeoFields v-model:seo="form.page.seo" />
        <a-button type="primary" :loading="form.processing" @click="submit">
          {{ t('admin.ui.save') }}
        </a-button>
      </a-card>
    </a-tab-pane>

    <a-tab-pane key="i18n" :title="t('admin.website.tabs.translations', 'Translations')">
      <div class="admin-form-card">
        <TranslationsPanel
          v-model:translations="form.page.translations"
          :locales="locales"
          :fields="['title']"
        />
        <a-button type="primary" class="mt-4" :loading="form.processing" @click="submit">
          {{ t('admin.ui.save') }}
        </a-button>
      </div>
    </a-tab-pane>
  </a-tabs>
</template>

<style scoped>
.admin-form-card {
  max-width: 880px;
}
</style>
