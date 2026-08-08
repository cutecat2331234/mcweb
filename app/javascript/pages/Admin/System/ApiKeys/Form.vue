<script setup lang="ts">
import { computed } from 'vue'
import { Link, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  title: string
  submitUrl: string
  backUrl: string
}>()

const form = useForm({
  api_key: { name: '', scopes: ['read'] as string[], username: '' },
})

const staffScopes = computed(() => [
  { value: 'staff.moderation.read', label: t('admin.apiKeys.scopeStaffRead') },
  { value: 'staff.moderation.claim', label: t('admin.apiKeys.scopeStaffClaim') },
  { value: 'staff.moderation.assign', label: t('admin.apiKeys.scopeStaffAssign') },
  { value: 'staff.moderation.note', label: t('admin.apiKeys.scopeStaffNote') },
  { value: 'staff.moderation.execute', label: t('admin.apiKeys.scopeStaffExecute') },
] as const)

const readScope = computed({
  get: () => form.api_key.scopes.includes('read'),
  set: (checked: boolean) => toggleScope('read', checked),
})

const writeScope = computed({
  get: () => form.api_key.scopes.includes('write'),
  set: (checked: boolean) => toggleScope('write', checked),
})

function toggleScope(scope: string, checked: boolean) {
  const scopes = new Set(form.api_key.scopes)
  if (checked) scopes.add(scope)
  else scopes.delete(scope)
  form.api_key.scopes = Array.from(scopes)
}

function hasScope(scope: string) {
  return form.api_key.scopes.includes(scope)
}

function setScope(scope: string, checked: boolean) {
  const scopes = new Set(form.api_key.scopes)
  if (checked) scopes.add(scope)
  else scopes.delete(scope)

  if (checked && scope !== 'staff.moderation.read') {
    scopes.add('staff.moderation.read')
  }
  if (!checked && scope === 'staff.moderation.read') {
    staffScopes.value.forEach((staffScope) => scopes.delete(staffScope.value))
  }
  form.api_key.scopes = Array.from(scopes)
}

function fieldError(field: string) {
  return form.errors[field] || form.errors[`api_key.${field}`]
}

function submit(event?: { errors?: unknown }) {
  if (event?.errors) return
  form.post(props.submitUrl)
}
</script>

<template>
  <section class="admin-system-api-key-form">
    <a-page-header :title="title" :show-back="false" class="mb-4 !px-0" />

    <a-card class="max-w-2xl" :bordered="true">
      <a-form :model="form.api_key" layout="vertical" @submit="submit">
        <a-form-item
          field="name"
          :label="t('admin.apiKeys.name')"
          :rules="[{ required: true, message: t('admin.apiKeys.name') }]"
          :validate-status="fieldError('name') ? 'error' : undefined"
          :help="fieldError('name')"
        >
          <a-input
            v-model="form.api_key.name"
            :max-length="80"
            show-word-limit
            allow-clear
          />
        </a-form-item>

        <a-form-item
          field="scopes"
          :label="t('admin.apiKeys.scopes')"
          :validate-status="fieldError('scopes') ? 'error' : undefined"
          :help="fieldError('scopes')"
        >
          <a-space direction="vertical" :size="10">
            <a-checkbox v-model="readScope">
              {{ t('admin.apiKeys.scopeRead') }}
            </a-checkbox>
            <a-checkbox v-model="writeScope">
              {{ t('admin.apiKeys.scopeWrite') }}
            </a-checkbox>
            <a-divider :margin="4" />
            <a-typography-text bold>
              {{ t('admin.apiKeys.staffScopes') }}
            </a-typography-text>
            <a-typography-text type="secondary">
              {{ t('admin.apiKeys.staffScopesHint') }}
            </a-typography-text>
            <a-checkbox
              v-for="scope in staffScopes"
              :key="scope.value"
              :model-value="hasScope(scope.value)"
              @change="setScope(scope.value, $event)"
            >
              {{ scope.label }}
            </a-checkbox>
          </a-space>
        </a-form-item>

        <a-form-item
          field="username"
          :label="t('admin.apiKeys.actAsUser')"
          :validate-status="fieldError('username') ? 'error' : undefined"
          :help="fieldError('username') || t('admin.apiKeys.actAsUserHint')"
        >
          <a-input
            v-model="form.api_key.username"
            :placeholder="t('admin.apiKeys.actAsUserHint')"
            allow-clear
          />
        </a-form-item>

        <a-space wrap>
          <a-button
            type="primary"
            html-type="submit"
            :loading="form.processing"
          >
            {{ t('admin.apiKeys.create') }}
          </a-button>
          <Link
            :href="backUrl"
            class="arco-btn arco-btn-outline arco-btn-size-medium no-underline"
          >
            {{ t('admin.ui.back') }}
          </Link>
        </a-space>
      </a-form>
    </a-card>
  </section>
</template>
