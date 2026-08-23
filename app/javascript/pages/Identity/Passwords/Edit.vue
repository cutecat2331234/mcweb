<script setup lang="ts">
import { computed, watch } from 'vue'
import { router, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import {
  Alert,
  Button,
  Card,
  Form,
  FormItem,
  Input,
  InputPassword,
  PageHeader,
  Space,
} from '@mcweb/ui'
import PortalLayout from '@/layouts/PortalLayout.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const props = defineProps<{
  totp_enabled: boolean
  form_errors?: Record<string, string> | null
}>()

const { t } = useI18n()

const form = useForm({
  password_change: {
    current_password: '',
    new_password: '',
    new_password_confirmation: '',
    code: '',
  },
})

watch(
  () => props.form_errors,
  (errors) => {
    form.clearErrors()
    if (!errors) return
    Object.entries(errors).forEach(([key, message]) => {
      form.setError(key as keyof typeof form.errors, message)
    })
  },
  { immediate: true },
)

const baseError = computed(() => form.errors.base || props.form_errors?.base || '')

function fieldError(field: keyof typeof form.password_change) {
  const key = `password_change.${field}`
  return form.errors[key as keyof typeof form.errors] || props.form_errors?.[key] || ''
}

function submit() {
  form.patch(routes.securityPassword, {
    preserveScroll: true,
    onSuccess: () => form.reset(),
  })
}
</script>

<template>
  <Space direction="vertical" fill size="large">
    <PageHeader
      :title="t('identity.password.title')"
      :subtitle="t('identity.password.subtitle')"
      @back="router.visit(routes.security)"
    />

    <Card :title="t('identity.password.formTitle')" :bordered="true">
      <Alert type="warning" show-icon class="mb-4">
        {{ t('identity.password.sessionNotice') }}
      </Alert>
      <Alert v-if="baseError" type="error" show-icon class="mb-4">
        {{ baseError }}
      </Alert>

      <Form :model="form.password_change" layout="vertical" class="max-w-xl" @submit="submit">
        <FormItem
          field="current_password"
          :label="t('identity.password.currentPassword')"
          :help="fieldError('current_password')"
          :validate-status="fieldError('current_password') ? 'error' : undefined"
          required
        >
          <InputPassword
            v-model="form.password_change.current_password"
            autocomplete="current-password"
          />
        </FormItem>

        <FormItem
          field="new_password"
          :label="t('identity.password.newPassword')"
          :help="fieldError('new_password') || t('identity.password.passwordHint')"
          :validate-status="fieldError('new_password') ? 'error' : undefined"
          required
        >
          <InputPassword
            v-model="form.password_change.new_password"
            autocomplete="new-password"
          />
        </FormItem>

        <FormItem
          field="new_password_confirmation"
          :label="t('identity.password.confirmPassword')"
          :help="fieldError('new_password_confirmation')"
          :validate-status="fieldError('new_password_confirmation') ? 'error' : undefined"
          required
        >
          <InputPassword
            v-model="form.password_change.new_password_confirmation"
            autocomplete="new-password"
          />
        </FormItem>

        <FormItem
          v-if="totp_enabled"
          field="code"
          :label="t('identity.password.twoFactorCode')"
          :help="fieldError('code') || t('identity.password.twoFactorHint')"
          :validate-status="fieldError('code') ? 'error' : undefined"
          required
        >
          <Input
            v-model="form.password_change.code"
            inputmode="text"
            autocomplete="one-time-code"
            autocapitalize="characters"
            :spellcheck="false"
            :placeholder="t('identity.password.twoFactorPlaceholder')"
          />
        </FormItem>

        <Space wrap>
          <Button type="primary" html-type="submit" :loading="form.processing" :disabled="form.processing">
            {{ t('identity.password.submit') }}
          </Button>
          <Button type="secondary" html-type="button" @click="router.visit(routes.security)">
            {{ t('identity.password.cancel') }}
          </Button>
        </Space>
      </Form>
    </Card>
  </Space>
</template>
