<script setup lang="ts">
import { computed, ref } from 'vue'
import { router, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import HighRiskActionModal from '@/components/admin/HighRiskActionModal.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  title: string
  membership_types: Array<{ id: number; name: string }>
  submitUrl: string
  authorizationUrl: string
  backUrl: string
}>()

const form = useForm<any>({
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
const confirmationVisible = ref(false)
const highRiskPayload = computed(() => ({
  user_membership: {
    username: form.user_membership.username.trim(),
    membership_type_id: form.user_membership.membership_type_id,
    grant_game_permissions: form.user_membership.grant_game_permissions,
  },
}))

function fieldError(field: string) {
  return (form.errors as Record<string, string | undefined>)[field] || (form.errors as Record<string, string | undefined>)[`user_membership.${field}`]
}

function submit(event?: { errors?: unknown }) {
  if (event?.errors) return
  confirmationVisible.value = true
}

function completed(result: Record<string, unknown>) {
  const redirectUrl = result.redirect_url
  if (typeof redirectUrl === 'string' && redirectUrl.length > 0) {
    router.visit(redirectUrl)
  }
}
</script>

<template>
  <a-space direction="vertical" :size="24" fill>
    <a-page-header :title="title" :show-back="false" />

    <a-row justify="center">
      <a-col :xs="24" :md="22" :lg="18" :xl="14">
        <a-card :bordered="true">
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

            <a-divider />

            <a-space wrap>
              <a-button type="primary" html-type="submit">
                {{ t('admin.forms.userMembership.grant') }}
              </a-button>
              <a-button html-type="button" @click="router.visit(backUrl)">
                {{ t('admin.ui.cancel') }}
              </a-button>
            </a-space>
          </a-form>
        </a-card>
      </a-col>
    </a-row>

    <HighRiskActionModal
      v-model:visible="confirmationVisible"
      :title="t('admin.forms.userMembership.grantReviewTitle')"
      :authorization-url="authorizationUrl"
      :action-url="submitUrl"
      :payload="highRiskPayload"
      @completed="completed"
    />
  </a-space>
</template>
