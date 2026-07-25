<script setup lang="ts">
import { ref } from 'vue'
import { router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import { Modal } from '@mcweb/ui'
import { IconDelete, IconUpload } from '@arco-design/web-vue/es/icon'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

interface TemplateItem {
  id: number
  key: string
  name: string
  version: string
  scopes: string[]
  status: string
  checksum: string
  builtin?: boolean
  error_message?: string | null
  update_url: string
  preview_website_url?: string | null
  preview_portal_url?: string | null
  delete_url: string
}

const props = defineProps<{
  templates: TemplateItem[]
  activeWebsiteTemplate: string | null
  activePortalTemplate: string | null
  uploadUrl: string
  starterDownloadUrl: string
}>()

const uploading = ref(false)

function uploadTemplate(file: File) {
  uploading.value = true
  router.post(
    props.uploadUrl,
    { archive: file },
    {
      forceFormData: true,
      onFinish: () => {
        uploading.value = false
      },
    },
  )
  return false
}

function activate(template: TemplateItem, scope: 'website' | 'portal') {
  router.patch(template.update_url, { scope, template_key: template.key })
}

function deactivate(scope: 'website' | 'portal', template: TemplateItem) {
  router.patch(template.update_url, { scope, template_key: null })
}

function removeTemplate(template: TemplateItem) {
  if (template.builtin) return
  Modal.warning({
    title: t('admin.templates.deleteTitle'),
    content: t('admin.templates.deleteConfirm', { name: template.name }),
    okText: t('admin.ui.delete'),
    cancelText: t('admin.ui.cancel'),
    hideCancel: false,
    okButtonProps: { status: 'danger' },
    onOk: () => router.delete(template.delete_url),
  })
}

function isActive(template: TemplateItem, scope: 'website' | 'portal') {
  return scope === 'website'
    ? props.activeWebsiteTemplate === template.key
    : props.activePortalTemplate === template.key
}

function statusColor(status: string) {
  if (status === 'installed') return 'green'
  if (status === 'error') return 'red'
  return 'gray'
}
</script>

<template>
  <a-page-header
    :title="t('admin.templates.title')"
    :subtitle="t('admin.templates.subtitle')"
    :show-back="false"
  />

  <a-card :title="t('admin.templates.uploadTitle')" :bordered="true" class="mb-4">
    <a-typography-paragraph type="secondary">
      {{ t('admin.templates.uploadHint') }}
      <a-link href="/template-starter/manifest.json" target="_blank" rel="noopener">
        {{ t('admin.templates.manifestSpec') }}
      </a-link>
      {{ t('admin.templates.orDownload') }}
      <a-link :href="starterDownloadUrl">{{ t('admin.templates.samplePack') }}</a-link>
    </a-typography-paragraph>
    <a-upload
      accept=".zip,application/zip"
      :auto-upload="false"
      :show-file-list="false"
      :disabled="uploading"
      :before-upload="uploadTemplate"
    >
      <template #upload-button>
        <a-button type="primary" :loading="uploading">
          <template #icon><icon-upload /></template>
          {{ uploading ? t('admin.templates.uploading') : t('admin.templates.selectZip') }}
        </a-button>
      </template>
    </a-upload>
  </a-card>

  <a-space v-if="templates.length" direction="vertical" fill>
    <a-card
      v-for="template in templates"
      :key="template.id"
      :title="template.name"
      :bordered="true"
    >
      <template #extra>
        <a-button
          v-if="!template.builtin"
          type="text"
          status="danger"
          size="small"
          @click="removeTemplate(template)"
        >
          <template #icon><icon-delete /></template>
          {{ t('admin.ui.delete') }}
        </a-button>
      </template>

      <a-space wrap>
        <a-tag v-if="template.builtin" color="arcoblue">{{ t('admin.templates.builtin') }}</a-tag>
        <a-tag>{{ template.key }}</a-tag>
        <a-tag>v{{ template.version }}</a-tag>
        <a-tag :color="statusColor(template.status)">{{ template.status }}</a-tag>
      </a-space>
      <a-typography-paragraph type="secondary" class="mt-2">
        {{ t('admin.templates.scopes') }}{{ template.scopes.join(t('common.listSeparator')) }}
        <template v-if="template.checksum">
          · {{ t('admin.templates.checksum') }}{{ template.checksum.slice(0, 12) }}…
        </template>
      </a-typography-paragraph>
      <a-alert v-if="template.error_message" type="error" show-icon class="mb-3">
        {{ template.error_message }}
      </a-alert>

      <a-space wrap>
        <template v-if="template.scopes.includes('website')">
          <a-button
            v-if="!isActive(template, 'website')"
            type="primary"
            size="small"
            @click="activate(template, 'website')"
          >
            {{ t('admin.templates.activateWebsite') }}
          </a-button>
          <a-button
            v-else-if="!template.builtin"
            size="small"
            @click="deactivate('website', template)"
          >
            {{ t('admin.templates.deactivateWebsite') }}
          </a-button>
          <a-tag v-else color="green">{{ t('admin.templates.builtinDefault') }}</a-tag>
          <a-link
            v-if="template.preview_website_url"
            :href="template.preview_website_url"
            target="_blank"
            rel="noopener"
          >
            {{ t('admin.templates.previewWebsite') }}
          </a-link>
        </template>

        <template v-if="template.scopes.includes('portal')">
          <a-button
            v-if="!isActive(template, 'portal')"
            type="primary"
            size="small"
            @click="activate(template, 'portal')"
          >
            {{ t('admin.templates.activatePortal') }}
          </a-button>
          <a-button
            v-else-if="!template.builtin"
            size="small"
            @click="deactivate('portal', template)"
          >
            {{ t('admin.templates.deactivatePortal') }}
          </a-button>
          <a-tag v-else color="green">{{ t('admin.templates.builtinDefault') }}</a-tag>
          <a-link
            v-if="template.preview_portal_url"
            :href="template.preview_portal_url"
            target="_blank"
            rel="noopener"
          >
            {{ t('admin.templates.previewPortal') }}
          </a-link>
        </template>
      </a-space>
    </a-card>
  </a-space>
  <a-empty v-else :description="t('admin.templates.loading')" />

  <a-alert type="info" class="mt-4">
    {{ t('admin.templates.activeNow') }}
    {{ t('admin.templates.website') }}
    <a-typography-text code>
      {{ activeWebsiteTemplate || t('admin.templates.builtinDefault') }}
    </a-typography-text>
    ·
    {{ t('admin.templates.portal') }}
    <a-typography-text code>
      {{ activePortalTemplate || t('admin.templates.builtinDefault') }}
    </a-typography-text>
  </a-alert>
</template>
