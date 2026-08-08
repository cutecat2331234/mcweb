<script setup lang="ts">
import { computed, watch } from 'vue'
import { Link, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AuthLayout from '@/layouts/AuthLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Alert from '@/components/ui/Alert.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: AuthLayout })

const props = defineProps<{
  token: string
  form_errors?: Record<string, string>
}>()

const { t } = useI18n()
const form = useForm({
  totp_recovery: {
    password: '',
  },
})

watch(
  () => props.form_errors,
  (errors) => {
    if (!errors) return
    Object.entries(errors).forEach(([key, message]) => {
      form.setError(key as keyof typeof form.errors, message)
    })
  },
  { immediate: true },
)

const formError = computed(() => form.errors.base || props.form_errors?.base || '')

function submit() {
  form.patch(routes.updateTotpRecovery(props.token))
}
</script>

<template>
  <PageHeader
    :title="t('identity.totpRecovery.completeTitle')"
    :subtitle="t('identity.totpRecovery.completeSubtitle')"
  />

  <div class="max-w-md space-y-4">
    <Alert
      v-if="formError"
      variant="destructive"
      :title="t('identity.totpRecovery.failedTitle')"
    >
      {{ formError }}
    </Alert>
    <Alert :title="t('identity.totpRecovery.sessionWarningTitle')">
      {{ t('identity.totpRecovery.sessionWarning') }}
    </Alert>

    <form class="space-y-4" @submit.prevent="submit">
      <div class="space-y-2">
        <Label for="totp_recovery_password">{{ t('auth.signIn.password') }}</Label>
        <Input
          id="totp_recovery_password"
          v-model="form.totp_recovery.password"
          type="password"
          autocomplete="current-password"
          required
        />
      </div>
      <div class="flex flex-wrap items-center gap-3">
        <Button type="submit" :disabled="form.processing">
          {{ t('identity.totpRecovery.reset') }}
        </Button>
        <Link :href="routes.signIn" class="text-sm text-muted-foreground hover:text-foreground">
          {{ t('auth.passwordReset.backToSignIn') }}
        </Link>
      </div>
    </form>
  </div>
</template>
