<script setup lang="ts">
import { ref } from 'vue'
import { Link, router } from '@inertiajs/vue3'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Badge from '@/components/ui/Badge.vue'

defineOptions({ layout: AdminLayout })

interface TemplateItem {
  id: number
  key: string
  name: string
  version: string
  scopes: string[]
  status: string
  checksum: string
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

function onFileChange(event: Event) {
  const input = event.target as HTMLInputElement
  const file = input.files?.[0]
  if (!file) return
  uploading.value = true
  router.post(props.uploadUrl, { archive: file }, {
    forceFormData: true,
    onFinish: () => { uploading.value = false; input.value = '' },
  })
}

function activate(template: TemplateItem, scope: 'website' | 'portal') {
  router.patch(template.update_url, { scope, template_key: template.key })
}

function deactivate(scope: 'website' | 'portal', template: TemplateItem) {
  router.patch(template.update_url, { scope, template_key: null })
}

function removeTemplate(template: TemplateItem) {
  if (!window.confirm(`确定删除模板「${template.name}」？`)) return
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
    title="前台模板"
    subtitle="上传 ZIP 压缩包快速更换官网与用户前台外观。后台 Admin 界面不受模板影响。"
  />

  <div class="mb-6 rounded-lg border p-4">
    <h2 class="mb-2 text-sm font-semibold">上传模板包</h2>
    <p class="mb-3 text-sm text-muted-foreground">
      压缩包需包含 manifest.json，详见
      <a href="/template-starter/manifest.json" class="underline" target="_blank" rel="noopener">manifest 规范</a>
      或下载
      <a :href="starterDownloadUrl" class="underline">示例模板包</a>。
    </p>
    <label class="inline-flex cursor-pointer items-center gap-2">
      <Button as-child variant="outline" size="sm" :disabled="uploading">
        <span>{{ uploading ? '上传中…' : '选择 ZIP 文件' }}</span>
      </Button>
      <input type="file" accept=".zip,application/zip" class="hidden" :disabled="uploading" @change="onFileChange">
    </label>
  </div>

  <div class="space-y-4">
    <div
      v-for="template in templates"
      :key="template.id"
      class="rounded-lg border p-4"
    >
      <div class="flex flex-wrap items-start justify-between gap-3">
        <div>
          <div class="flex flex-wrap items-center gap-2">
            <h3 class="font-medium">{{ template.name }}</h3>
            <Badge variant="outline">{{ template.key }}</Badge>
            <Badge variant="outline">v{{ template.version }}</Badge>
            <Badge :variant="template.status === 'installed' ? 'default' : 'outline'">{{ template.status }}</Badge>
          </div>
          <p class="mt-1 text-xs text-muted-foreground">
            范围：{{ template.scopes.join('、') }}
            <span v-if="template.checksum" class="ml-2">校验：{{ template.checksum.slice(0, 12) }}…</span>
          </p>
          <p v-if="template.error_message" class="mt-1 text-sm text-destructive">{{ template.error_message }}</p>
        </div>
        <Button type="button" variant="outline" size="sm" @click="removeTemplate(template)">删除</Button>
      </div>

      <div class="mt-4 flex flex-wrap gap-2">
        <template v-if="template.scopes.includes('website')">
          <Button
            v-if="!isActive(template, 'website')"
            type="button"
            size="sm"
            @click="activate(template, 'website')"
          >
            激活官网
          </Button>
          <Button
            v-else
            type="button"
            size="sm"
            variant="secondary"
            @click="deactivate('website', template)"
          >
            停用官网
          </Button>
          <Button v-if="template.preview_website_url" as-child size="sm" variant="outline">
            <a :href="template.preview_website_url" target="_blank" rel="noopener">预览官网</a>
          </Button>
        </template>

        <template v-if="template.scopes.includes('portal')">
          <Button
            v-if="!isActive(template, 'portal')"
            type="button"
            size="sm"
            @click="activate(template, 'portal')"
          >
            激活前台
          </Button>
          <Button
            v-else
            type="button"
            size="sm"
            variant="secondary"
            @click="deactivate('portal', template)"
          >
            停用前台
          </Button>
          <Button v-if="template.preview_portal_url" as-child size="sm" variant="outline">
            <a :href="template.preview_portal_url" target="_blank" rel="noopener">预览前台</a>
          </Button>
        </template>
      </div>
    </div>

    <p v-if="!templates.length" class="text-sm text-muted-foreground">尚未安装任何前台模板。</p>
  </div>

  <p class="mt-6 text-xs text-muted-foreground">
    当前激活：
    官网 <code>{{ activeWebsiteTemplate || '默认' }}</code>，
    前台 <code>{{ activePortalTemplate || '默认' }}</code>
  </p>
</template>
