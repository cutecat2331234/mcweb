<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

const props = defineProps<{
  title: string
  userField: {
    key: string
    label: string
    field_type: string
    description: string
    choices: string
    sort_order: number
    visibility: string
    required: boolean
    show_on_registration: boolean
    show_on_profile: boolean
    editable_by_user: boolean
    active: boolean
  }
  submitUrl: string
  method: 'post' | 'patch'
  backUrl: string
}>()

const { t } = useI18n()
const form = useForm({ user_field: { ...props.userField } })

const fieldTypes = [
  { value: 'text', label: 'text' },
  { value: 'textarea', label: 'textarea' },
  { value: 'number', label: 'number' },
  { value: 'url', label: 'url' },
  { value: 'select', label: 'select' },
  { value: 'checkbox', label: 'checkbox' },
]

const visibilities = [
  { value: 'public', label: 'public' },
  { value: 'owner', label: 'owner' },
  { value: 'staff', label: 'staff' },
]

function submit() {
  if (props.method === 'patch') form.patch(props.submitUrl)
  else form.post(props.submitUrl)
}
</script>

<template>
  <a-page-header :title="title" :show-back="false" class="mb-4 !px-0" />
  <a-card class="max-w-3xl" :bordered="true">
    <form class="grid gap-4" @submit.prevent="submit">
      <a-row :gutter="[16, 0]">
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('adminMinecraft.colKey') }}</span>
            <a-input
              v-model="form.user_field.key"
              :input-attrs="{ required: true, pattern: '[a-z][a-z0-9_]*' }"
              allow-clear
            />
          </label>
        </a-col>
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('adminMinecraft.colLabel') }}</span>
            <a-input v-model="form.user_field.label" :input-attrs="{ required: true }" allow-clear />
          </label>
        </a-col>
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('adminMinecraft.colType') }}</span>
            <a-select v-model="form.user_field.field_type" :options="fieldTypes" />
          </label>
        </a-col>
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('adminMinecraft.colVisibility') }}</span>
            <a-select v-model="form.user_field.visibility" :options="visibilities" />
          </label>
        </a-col>
      </a-row>
      <label class="admin-forum-field">
        <span>{{ t('adminForum.fieldDescription') }}</span>
        <a-textarea v-model="form.user_field.description" :auto-size="{ minRows: 2, maxRows: 6 }" />
      </label>
      <label v-if="form.user_field.field_type === 'select'" class="admin-forum-field">
        <span>{{ t('adminForum.fieldChoices') }}</span>
        <a-textarea
          v-model="form.user_field.choices"
          :auto-size="{ minRows: 4, maxRows: 10 }"
          :placeholder="t('adminForum.fieldChoicesPlaceholder')"
        />
      </label>
      <label class="admin-forum-field">
        <span>{{ t('adminMinecraft.sortOrder') }}</span>
        <a-input-number v-model="form.user_field.sort_order" class="w-full sm:w-48" />
      </label>
      <a-card size="small" :bordered="true">
        <a-space direction="vertical" align="start">
          <a-checkbox v-model="form.user_field.required">{{ t('adminForum.fieldRequired') }}</a-checkbox>
          <a-checkbox v-model="form.user_field.show_on_registration">{{ t('adminForum.fieldShowOnRegistration') }}</a-checkbox>
          <a-checkbox v-model="form.user_field.show_on_profile">{{ t('adminForum.fieldShowOnProfile') }}</a-checkbox>
          <a-checkbox v-model="form.user_field.editable_by_user">{{ t('adminForum.fieldEditableByUser') }}</a-checkbox>
          <a-checkbox v-model="form.user_field.active">{{ t('adminMinecraft.active') }}</a-checkbox>
        </a-space>
      </a-card>
      <a-space wrap>
        <a-button html-type="submit" type="primary" :loading="form.processing">{{ t('common.save') }}</a-button>
        <Link :href="backUrl" class="arco-btn arco-btn-outline arco-btn-size-medium no-underline">{{ t('common.cancel') }}</Link>
      </a-space>
    </form>
  </a-card>
</template>

<style scoped>
.admin-forum-field { display: grid; gap: 6px; color: var(--color-text-2); font-size: 14px; }
</style>
