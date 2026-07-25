<script setup lang="ts">
import { router, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

const props = defineProps<{
  title: string
  profileField: {
    key: string
    label: string
    field_type: string
    icon: string
    sort_order: number
    visibility: string
    source: string
    group_name: string
    active: boolean
  }
  submitUrl: string
  method: 'post' | 'patch'
  backUrl: string
}>()

const { t } = useI18n()
const form = useForm({ profile_field: { ...props.profileField } })

const fieldTypes = ['text', 'number', 'url', 'markdown', 'badge', 'link', 'json'].map(
  (value) => ({ value, label: value }),
)
const visibilities = ['public', 'owner', 'staff'].map((value) => ({ value, label: value }))

function submit() {
  if (props.method === 'patch') form.patch(props.submitUrl)
  else form.post(props.submitUrl)
}
</script>

<template>
  <a-page-header :title="title" :show-back="false" />
  <a-card class="admin-form-card" :bordered="true">
    <a-form :model="form.profile_field" layout="vertical" @submit="submit">
      <a-grid :cols="{ xs: 1, sm: 2 }" :col-gap="16">
        <a-grid-item>
          <a-form-item field="key" :label="t('adminMinecraft.colKey')" required>
            <a-input v-model="form.profile_field.key" allow-clear />
          </a-form-item>
        </a-grid-item>
        <a-grid-item>
          <a-form-item field="label" :label="t('adminMinecraft.colLabel')" required>
            <a-input v-model="form.profile_field.label" allow-clear />
          </a-form-item>
        </a-grid-item>
        <a-grid-item>
          <a-form-item field="field_type" :label="t('adminMinecraft.colType')">
            <a-select v-model="form.profile_field.field_type" :options="fieldTypes" />
          </a-form-item>
        </a-grid-item>
        <a-grid-item>
          <a-form-item field="visibility" :label="t('adminMinecraft.colVisibility')">
            <a-select v-model="form.profile_field.visibility" :options="visibilities" />
          </a-form-item>
        </a-grid-item>
      </a-grid>
      <a-form-item field="source" :label="t('adminMinecraft.colSource')">
        <a-input
          v-model="form.profile_field.source"
          placeholder="bridge:papi:player_level"
          allow-clear
        />
      </a-form-item>
      <a-form-item field="group_name" :label="t('adminMinecraft.groupName')">
        <a-input v-model="form.profile_field.group_name" allow-clear />
      </a-form-item>
      <a-form-item field="sort_order" :label="t('adminMinecraft.sortOrder')">
        <a-input-number v-model="form.profile_field.sort_order" :precision="0" />
      </a-form-item>
      <a-form-item field="active" :label="t('adminMinecraft.active')">
        <a-switch v-model="form.profile_field.active" />
      </a-form-item>
      <a-space>
        <a-button html-type="submit" type="primary" :loading="form.processing">
          {{ t('common.save') }}
        </a-button>
        <a-button @click="router.visit(backUrl)">{{ t('common.cancel') }}</a-button>
      </a-space>
    </a-form>
  </a-card>
</template>

<style scoped>
.admin-form-card {
  max-width: 760px;
}
</style>
