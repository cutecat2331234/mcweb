<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { confirm } from '@/lib/arcoConfirm'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  title: string
  forum_theme: { name: string; primary_color: string; accent_color: string; is_default: boolean; active: boolean }
  submitUrl: string
  method?: 'post' | 'patch'
  backUrl: string
  deleteUrl?: string | null
}>()

const form = useForm({ forum_theme: { ...props.forum_theme } })

function submit() {
  if (props.method === 'patch') {
    form.patch(props.submitUrl)
  } else {
    form.post(props.submitUrl)
  }
}

async function destroy() {
  const ok = await confirm({
    title: t('admin.forumThemesForm.deleteTitle'),
    message: t('admin.forumThemesForm.deleteConfirm'),
    confirmLabel: t('admin.ui.delete'),
    variant: 'destructive',
  })
  if (!props.deleteUrl || !ok) return
  form.delete(props.deleteUrl)
}
</script>

<template>
  <a-page-header :title="title" :show-back="false" class="mb-4 !px-0" />
  <a-card class="max-w-xl" :bordered="true">
    <form class="grid gap-4" @submit.prevent="submit">
      <label class="admin-forum-field">
        <span>{{ t('admin.forumThemesForm.name') }}</span>
        <a-input v-model="form.forum_theme.name" :input-attrs="{ required: true, maxlength: 100 }" allow-clear />
      </label>
      <a-row :gutter="[16, 0]">
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('admin.forumThemesForm.primaryColor') }}</span>
            <a-input v-model="form.forum_theme.primary_color" placeholder="#6366f1" allow-clear />
          </label>
        </a-col>
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('admin.forumThemesForm.accentColor') }}</span>
            <a-input v-model="form.forum_theme.accent_color" placeholder="#a5b4fc" allow-clear />
          </label>
        </a-col>
      </a-row>
      <a-alert type="info">{{ t('admin.forumThemesForm.colorHint') }}</a-alert>
      <a-space direction="vertical" align="start">
        <a-checkbox v-model="form.forum_theme.is_default">{{ t('admin.forumThemesForm.isDefault') }}</a-checkbox>
        <a-checkbox v-model="form.forum_theme.active">{{ t('admin.forumThemesForm.active') }}</a-checkbox>
      </a-space>
      <a-space wrap>
        <a-button html-type="submit" type="primary" :loading="form.processing">{{ t('admin.ui.save') }}</a-button>
        <a-button v-if="deleteUrl" type="primary" status="danger" @click="destroy">{{ t('admin.ui.delete') }}</a-button>
        <Link :href="backUrl" class="arco-btn arco-btn-outline arco-btn-size-medium no-underline">{{ t('admin.ui.back') }}</Link>
      </a-space>
    </form>
  </a-card>
</template>

<style scoped>
.admin-forum-field { display: grid; gap: 6px; color: var(--color-text-2); font-size: 14px; }
</style>
