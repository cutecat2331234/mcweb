<script setup lang="ts">
import { ref } from 'vue'
import { Link, router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Badge from '@/components/ui/Badge.vue'
import FileInput from '@/components/ui/FileInput.vue'
import { confirm } from '@/lib/useConfirm'

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

function onFileChange(file: File) {
  uploading.value = true
  router.post(props.uploadUrl, { archive: file }, {
    forceFormData: true,
    onFinish: () => { uploading.value = false },
  })
}

function activate(template: TemplateItem, scope: 'website' | 'portal') {
  router.patch(template.update_url, { scope, template_key: template.key })
}

function deactivate(scope: 'website' | 'portal', template: TemplateItem) {
  router.patch(template.update_url, { scope, template_key: null })
}

async function removeTemplate(template: TemplateItem) {
  if (template.builtin) return
  const ok = await confirm({
    title: t('admin.templates.deleteTitle'),
    message: t('admin.templates.deleteConfirm', { name: template.name }),
    confirmLabel: t('admin.ui.delete'),
    variant: 'destructive',
  })
  if (!ok) return
  router.delete(template.delete_url)
}

function isActive(template: TemplateItem, scope: 'website' | 'portal') {
  return scope === 'website'
    ? props.activeWebsiteTemplate === template.key
    : props.activePortalTemplate === template.key
}
</script>

<template>
  <PageHeader
    :title="t('admin.templates.title')"
    :subtitle="t('admin.templates.subtitle')"
  />

  <div class="mb-6 rounded-lg border p-4">
    <h2 class="mb-2 text-sm font-semibold">{{ t('admin.templates.uploadTitle') }}</h2>
    <p class="mb-3 text-sm text-muted-foreground">
      {{ t('admin.templates.uploadHint') }}
      <a href="/template-starter/manifest.json" class="underline" target="_blank" rel="noopener">{{ t('admin.templates.manifestSpec') }}</a>
      {{ t('admin.templates.orDownload') }}
      <a :href="starterDownloadUrl" class="underline">{{ t('admin.templates.samplePack') }}</a>。
    </p>
    <FileInput
      accept=".zip,application/zip"
      :disabled="uploading"
      :button-label="uploading ? t('admin.templates.uploading') : t('admin.templates.selectZip')"
      @change="onFileChange"
    />
  </div>

  <div class="space-y-4">
    <div
      v-for="template in templates"
      :key="template.id"
      class="rounded-lg border p-4"
    >
      <div class="flex flex-wrap items-start justify-between gap-3">
        <div class="min-w-0 flex-1">
          <div class="flex flex-wrap items-center gap-2">
            <h3 class="font-medium">{{ template.name }}</h3>
            <Badge v-if="template.builtin" variant="secondary">{{ t('admin.templates.builtin') }}</Badge>
            <Badge variant="outline">{{ template.key }}</Badge>
            <Badge variant="outline">v{{ template.version }}</Badge>
            <Badge :variant="template.status === 'installed' ? 'default' : 'outline'">{{ template.status }}</Badge>
          </div>
          <p class="mt-1 text-xs text-muted-foreground">
            {{ t('admin.templates.scopes') }}{{ template.scopes.join(t('common.listSeparator')) }}
            <span v-if="template.checksum" class="ml-2">{{ t('admin.templates.checksum') }}{{ template.checksum.slice(0, 12) }}…</span>
          </p>
          <p v-if="template.error_message" class="mt-1 text-sm text-destructive">{{ template.error_message }}</p>
        </div>
        <Button
          v-if="!template.builtin"
          type="button"
          variant="outline"
          size="sm"
          @click="removeTemplate(template)"
        >
          {{ t('admin.ui.delete') }}
        </Button>
      </div>

      <div class="mt-4 flex flex-wrap items-center justify-end gap-2 sm:justify-start">
        <template v-if="template.scopes.includes('website')">
          <Button
            v-if="!isActive(template, 'website')"
            type="button"
            size="sm"
            @click="activate(template, 'website')"
          >
            {{ t('admin.templates.activateWebsite') }}
          </Button>
          <Button
            v-else-if="!template.builtin"
            type="button"
            size="sm"
            variant="secondary"
            @click="deactivate('website', template)"
          >
            {{ t('admin.templates.deactivateWebsite') }}
          </Button>
          <Badge v-else-if="isActive(template, 'website')" variant="secondary">{{ t('admin.templates.builtinDefault') }}</Badge>
          <Button v-if="template.preview_website_url" as-child size="sm" variant="outline">
            <a :href="template.preview_website_url" target="_blank" rel="noopener">{{ t('admin.templates.previewWebsite') }}</a>
          </Button>
        </template>

        <template v-if="template.scopes.includes('portal')">
          <Button
            v-if="!isActive(template, 'portal')"
            type="button"
            size="sm"
            @click="activate(template, 'portal')"
          >
            {{ t('admin.templates.activatePortal') }}
          </Button>
          <Button
            v-else-if="!template.builtin"
            type="button"
            size="sm"
            variant="secondary"
            @click="deactivate('portal', template)"
          >
            {{ t('admin.templates.deactivatePortal') }}
          </Button>
          <Badge v-else-if="isActive(template, 'portal')" variant="secondary">{{ t('admin.templates.builtinDefault') }}</Badge>
          <Button v-if="template.preview_portal_url" as-child size="sm" variant="outline">
            <a :href="template.preview_portal_url" target="_blank" rel="noopener">{{ t('admin.templates.previewPortal') }}</a>
          </Button>
        </template>
      </div>
    </div>

    <p v-if="!templates.length" class="text-sm text-muted-foreground">{{ t('admin.templates.loading') }}</p>
  </div>

  <p class="mt-6 text-xs text-muted-foreground">
    {{ t('admin.templates.activeNow') }}
    {{ t('admin.templates.website') }} <code>{{ activeWebsiteTemplate || t('admin.templates.builtinDefault') }}</code>，
    {{ t('admin.templates.portal') }} <code>{{ activePortalTemplate || t('admin.templates.builtinDefault') }}</code>
  </p>
</template>
