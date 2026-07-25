<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { confirm } from '@/lib/arcoConfirm'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  title: string
  smilie: { code: string; emoji: string; title: string; position: number; active: boolean }
  submitUrl: string
  method?: 'post' | 'patch'
  backUrl: string
  deleteUrl?: string | null
}>()

const form = useForm({ smilie: { ...props.smilie } })

function submit() {
  if (props.method === 'patch') {
    form.patch(props.submitUrl)
  } else {
    form.post(props.submitUrl)
  }
}

async function destroy() {
  const ok = await confirm({
    title: t('admin.smilies.deleteTitle'),
    message: t('admin.smilies.deleteConfirm'),
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
      <a-row :gutter="[16, 0]">
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('admin.smilies.code') }}</span>
            <a-input v-model="form.smilie.code" :placeholder="':)'" :input-attrs="{ required: true, maxlength: 40 }" allow-clear />
          </label>
        </a-col>
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('admin.smilies.emoji') }}</span>
            <a-input v-model="form.smilie.emoji" placeholder="😊" :input-attrs="{ required: true, maxlength: 40 }" allow-clear />
          </label>
        </a-col>
      </a-row>
      <label class="admin-forum-field">
        <span>{{ t('admin.smilies.titleLabel') }}</span>
        <a-input v-model="form.smilie.title" allow-clear />
      </label>
      <label class="admin-forum-field">
        <span>{{ t('admin.smilies.position') }}</span>
        <a-input-number v-model="form.smilie.position" :min="0" class="w-full" />
      </label>
      <a-checkbox v-model="form.smilie.active">{{ t('admin.smilies.active') }}</a-checkbox>
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
