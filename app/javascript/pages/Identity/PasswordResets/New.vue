<script setup lang="ts">
import { computed } from 'vue'
import { Link, useForm, usePage } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AuthLayout from '@/layouts/AuthLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Alert from '@/components/ui/Alert.vue'
import { routes } from '@/lib/routes'
import { csrfHeaders, readCsrfToken } from '@/lib/csrf'

defineOptions({ layout: AuthLayout })

const props = defineProps<{
  form_error?: string
}>()

const page = usePage()
const { t } = useI18n()

const form = useForm({
  password_reset: { email: '' },
})

const formError = computed(() => {
  if (form.errors.base) return form.errors.base
  if (props.form_error) return props.form_error
  const pageErrors = page.props.errors as Record<string, string> | undefined
  return pageErrors?.base || ''
})

function submit() {
  const token = String(page.props.csrf_token || readCsrfToken())
  form
    .transform((data) => ({ ...data, authenticity_token: token }))
    .post(routes.identityPasswordResets, {
      preserveScroll: true,
      headers: csrfHeaders(),
    })
}
</script>

<template>
  <PageHeader density="compact" :title="t('auth.passwordReset.title')" :subtitle="t('auth.passwordReset.subtitle')" />

  <Alert v-if="formError" variant="destructive" :title="t('auth.passwordReset.sendFailed')" class="mb-4 max-w-md">
    {{ formError }}
  </Alert>

  <form class="w-full space-y-5" @submit.prevent="submit">
    <div class="space-y-2">
      <Label for="email">{{ t('auth.passwordReset.email') }}</Label>
      <Input id="email" v-model="form.password_reset.email" density="comfortable" type="email" required autofocus />
    </div>
    <div class="flex flex-col items-stretch gap-4 sm:flex-row sm:items-center sm:justify-between">
      <Button class="w-full sm:w-auto" size="comfortable" type="submit" :disabled="form.processing">{{ t('auth.passwordReset.submit') }}</Button>
      <Link :href="routes.signIn" class="text-sm text-muted-foreground hover:text-foreground">{{ t('auth.passwordReset.backToSignIn') }}</Link>
    </div>
  </form>
</template>
