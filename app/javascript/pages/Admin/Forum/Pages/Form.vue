<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { confirm } from '@/lib/arcoConfirm'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  title: string
  forum_page: { title: string; slug: string; body: string; show_in_nav: boolean; nav_label: string; position: number; published: boolean }
  submitUrl: string
  method?: 'post' | 'patch'
  backUrl: string
  deleteUrl?: string | null
}>()

const form = useForm({ forum_page: { ...props.forum_page } })

function submit() {
  if (props.method === 'patch') {
    form.patch(props.submitUrl)
  } else {
    form.post(props.submitUrl)
  }
}

async function destroy() {
  const ok = await confirm({
    title: t('admin.forumPagesForm.deleteTitle'),
    message: t('admin.forumPagesForm.deleteConfirm'),
    confirmLabel: t('admin.ui.delete'),
    variant: 'destructive',
  })
  if (!props.deleteUrl || !ok) return
  form.delete(props.deleteUrl)
}
</script>

<template>
  <a-page-header :title="title" :show-back="false" class="mb-4 !px-0" />
  <a-card class="max-w-3xl" :bordered="true">
    <form class="grid gap-4" @submit.prevent="submit">
      <label class="admin-forum-field">
        <span>{{ t('admin.forumPagesForm.title') }}</span>
        <a-input v-model="form.forum_page.title" :input-attrs="{ required: true, maxlength: 200 }" allow-clear />
      </label>
      <label class="admin-forum-field">
        <span>{{ t('admin.forumPagesForm.slug') }}</span>
        <a-input v-model="form.forum_page.slug" :placeholder="t('admin.forumPagesForm.slugHint')" allow-clear />
      </label>
      <label class="admin-forum-field">
        <span>{{ t('admin.forumPagesForm.body') }}</span>
        <a-textarea v-model="form.forum_page.body" :auto-size="{ minRows: 10, maxRows: 24 }" />
      </label>
      <a-checkbox v-model="form.forum_page.show_in_nav">{{ t('admin.forumPagesForm.showInNav') }}</a-checkbox>
      <a-row :gutter="[16, 0]">
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('admin.forumPagesForm.navLabel') }}</span>
            <a-input v-model="form.forum_page.nav_label" allow-clear />
          </label>
        </a-col>
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('admin.forumPagesForm.position') }}</span>
            <a-input-number v-model="form.forum_page.position" :min="0" class="w-full" />
          </label>
        </a-col>
      </a-row>
      <a-checkbox v-model="form.forum_page.published">{{ t('admin.forumPagesForm.published') }}</a-checkbox>
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
