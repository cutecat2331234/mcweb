<script setup lang="ts">
import { computed, watch } from 'vue'
import { Link, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AuthLayout from '@/layouts/AuthLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Alert from '@/components/ui/Alert.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: AuthLayout })

const props = defineProps<{
  token: string
  form_errors?: Record<string, string>
}>()

const { t } = useI18n()

const form = useForm({
  password_reset: {
    password: '',
    password_confirmation: '',
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
  form.patch(`/app/identity/password_resets/${props.token}`)
}
</script>

<template>
  <PageHeader density="compact" :title="t('auth.passwordReset.editTitle')" :subtitle="t('auth.passwordReset.editSubtitle')" />

  <Alert v-if="formError" variant="destructive" :title="t('auth.passwordReset.updateFailed')" class="mb-4 max-w-md">
    {{ formError }}
  </Alert>

  <form class="w-full space-y-5" @submit.prevent="submit">
    <div class="space-y-2">
      <Label for="password">{{ t('auth.passwordReset.newPassword') }}</Label>
      <Input id="password" v-model="form.password_reset.password" density="comfortable" type="password" required autocomplete="new-password" />
    </div>
    <div class="space-y-2">
      <Label for="password_confirmation">{{ t('auth.passwordReset.confirmPassword') }}</Label>
      <Input id="password_confirmation" v-model="form.password_reset.password_confirmation" density="comfortable" type="password" required autocomplete="new-password" />
    </div>
    <div class="flex flex-col items-stretch gap-4 sm:flex-row sm:items-center">
      <Button class="w-full sm:w-auto" size="comfortable" type="submit" :disabled="form.processing">{{ t('auth.passwordReset.updatePassword') }}</Button>
      <Link :href="routes.signIn" class="text-sm text-muted-foreground hover:text-foreground">{{ t('auth.passwordReset.backToSignIn') }}</Link>
    </div>
  </form>
</template>
