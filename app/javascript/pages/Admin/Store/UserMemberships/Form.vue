<script setup lang="ts">
import { computed } from 'vue'
import { Link, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  title: string
  membership_types: Array<{ id: number; name: string }>
  submitUrl: string
  backUrl: string
}>()

const form = useForm({
  user_membership: {
    username: '',
    membership_type_id: props.membership_types[0]?.id ?? null,
    grant_game_permissions: true,
  },
})

const typeOptions = computed(() =>
  props.membership_types.map((type) => ({
    value: type.id,
    label: type.name,
  })),
)

function fieldError(field: string) {
  return form.errors[field] || form.errors[`user_membership.${field}`]
}

function submit(event?: { errors?: unknown }) {
  if (event?.errors) return
  form.post(props.submitUrl)
}
</script>

<template>
  <section class="admin-store-user-membership-form">
    <a-page-header :title="title" :show-back="false" class="mb-4 !px-0" />

    <a-card class="max-w-2xl" :bordered="true">
      <a-form :model="form.user_membership" layout="vertical" @submit="submit">
        <a-form-item
          field="username"
          :label="t('admin.forms.userMembership.username')"
          :rules="[{ required: true, message: t('admin.forms.userMembership.username') }]"
          :validate-status="fieldError('username') ? 'error' : undefined"
          :help="fieldError('username')"
        >
          <a-input v-model="form.user_membership.username" allow-clear />
        </a-form-item>

        <a-form-item
          field="membership_type_id"
          :label="t('admin.forms.userMembership.type')"
          :validate-status="fieldError('membership_type_id') ? 'error' : undefined"
          :help="fieldError('membership_type_id')"
        >
          <a-select
            v-model="form.user_membership.membership_type_id"
            :options="typeOptions"
            allow-search
          />
        </a-form-item>

        <a-form-item
          field="grant_game_permissions"
          :label="t('admin.forms.userMembership.grantGamePermissions')"
          :validate-status="fieldError('grant_game_permissions') ? 'error' : undefined"
          :help="fieldError('grant_game_permissions')"
        >
          <a-switch v-model="form.user_membership.grant_game_permissions" />
        </a-form-item>

        <a-space wrap>
          <a-button type="primary" html-type="submit" :loading="form.processing">
            {{ t('admin.forms.userMembership.grant') }}
          </a-button>
          <Link
            :href="backUrl"
            class="arco-btn arco-btn-outline arco-btn-size-medium no-underline"
          >
            {{ t('admin.ui.cancel') }}
          </Link>
        </a-space>
      </a-form>
    </a-card>
  </section>
</template>
