<script setup lang="ts">
import { ref } from 'vue'
import { router, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import { Modal } from '@mcweb/ui'
import AdminLayout from '@/layouts/AdminLayout.vue'
import MarkdownEditor from '@/components/admin/MarkdownEditor.vue'
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
const form = useForm({ article: { ...props.article } })

function fieldError(key: string) {
  const inertiaError = form.errors[`article.${key}` as keyof typeof form.errors]
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
    content: t('admin.website.publishConfirm', 'Publish this article now?'),
    okText: t('admin.website.publish', 'Publish now'),
    cancelText: t('admin.ui.cancel'),
    hideCancel: false,
    onOk: () => router.post(props.publishUrl!),
  })
}

function schedulePublish() {
  if (props.scheduleUrl && scheduleAt.value) {
    router.post(props.scheduleUrl, { publish_at: scheduleAt.value })
  }
}
</script>

<template>
  <a-page-header :title="title" :show-back="false">
    <template #extra>
      <a-button @click="router.visit(backUrl)">{{ t('admin.ui.cancel') }}</a-button>
    </template>
  </a-page-header>

  <a-tabs v-model:active-key="tab" type="card-gutter">
    <a-tab-pane key="basic" :title="t('admin.website.tabs.basic', 'Basic')">
      <a-card :bordered="true" class="admin-form-card">
        <a-form :model="form.article" layout="vertical" @submit="submit">
          <a-form-item
            field="title"
            :label="t('admin.common.title')"
            required
            :validate-status="fieldError('title') ? 'error' : undefined"
            :help="fieldError('title')"
          >
            <a-input v-model="form.article.title" allow-clear />
          </a-form-item>
          <a-form-item
            field="slug"
            :label="t('admin.forms.category.slug')"
            required
            :validate-status="fieldError('slug') ? 'error' : undefined"
            :help="fieldError('slug')"
          >
            <a-input v-model="form.article.slug" allow-clear />
          </a-form-item>
          <a-form-item field="article_type" :label="t('admin.website.articleType')">
            <a-select v-model="form.article.article_type" :options="articleTypeOptions" />
          </a-form-item>
          <a-form-item :label="t('admin.common.status')">
            <a-tag>{{ form.article.status }}</a-tag>
          </a-form-item>
          <a-form-item
            field="summary"
            :label="t('admin.website.summary')"
            :validate-status="fieldError('summary') ? 'error' : undefined"
            :help="fieldError('summary')"
          >
            <a-textarea
              v-model="form.article.summary"
              :auto-size="{ minRows: 3, maxRows: 8 }"
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
              <a-button
                :disabled="!scheduleAt"
                @click="schedulePublish"
              >
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

    <a-tab-pane key="body" :title="t('admin.website.tabs.body', 'Body')">
      <a-card :bordered="true">
        <MarkdownEditor v-model="form.article.body" :rows="16" />
        <a-button type="primary" class="mt-4" :loading="form.processing" @click="submit">
          {{ t('admin.ui.save') }}
        </a-button>
      </a-card>
    </a-tab-pane>

    <a-tab-pane key="seo" title="SEO">
      <a-card :bordered="true" class="admin-form-card">
        <SeoFields v-model:seo="form.article.seo" />
        <a-button type="primary" :loading="form.processing" @click="submit">
          {{ t('admin.ui.save') }}
        </a-button>
      </a-card>
    </a-tab-pane>

    <a-tab-pane key="i18n" :title="t('admin.website.tabs.translations', 'Translations')">
      <div class="admin-form-card">
        <TranslationsPanel
          v-model:translations="form.article.translations"
          :locales="locales"
          :fields="['title', 'summary']"
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
