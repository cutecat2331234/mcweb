<script setup lang="ts">
import { computed } from 'vue'
import { Link, useForm, usePage } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Checkbox from '@/components/ui/Checkbox.vue'
import Alert from '@/components/ui/Alert.vue'
import { routes } from '@/lib/routes'
import { csrfHeaders, readCsrfToken } from '@/lib/csrf'

defineOptions({ layout: PortalLayout })

const props = defineProps<{
  login_error?: string
  errors?: Record<string, string>
}>()

const page = usePage()
const { t } = useI18n()

const form = useForm({
  session: {
    email: '',
    password: '',
    totp_code: '',
    remember_me: false,
  },
})

const loginError = computed(() => {
  if (form.errors.base) return form.errors.base
  if (props.login_error) return props.login_error
  const pageErrors = page.props.errors as Record<string, string> | undefined
  return pageErrors?.base || ''
})

function submit() {
  const token = String(page.props.csrf_token || readCsrfToken())
  form
    .transform((data) => ({ ...data, authenticity_token: token }))
    .post(routes.identitySession, {
      preserveScroll: true,
      headers: csrfHeaders(),
    })
}
</script>

<template>
  <PageHeader :title="t('auth.signIn.title')" :subtitle="t('auth.signIn.subtitle')" />

  <Alert v-if="loginError" variant="destructive" :title="t('auth.signIn.failed')" class="mb-4 max-w-md">
    {{ loginError }}
  </Alert>

  <form class="max-w-md space-y-4" @submit.prevent="submit">
    <div class="space-y-2">
      <Label for="email">{{ t('auth.signIn.email') }}</Label>
      <Input id="email" v-model="form.session.email" type="email" autocomplete="email" required autofocus />
      <p v-if="form.errors['session.email']" class="text-sm text-destructive">{{ form.errors['session.email'] }}</p>
    </div>

    <div class="space-y-2">
      <Label for="password">{{ t('auth.signIn.password') }}</Label>
      <Input id="password" v-model="form.session.password" type="password" autocomplete="current-password" required />
      <p v-if="form.errors['session.password']" class="text-sm text-destructive">{{ form.errors['session.password'] }}</p>
    </div>

    <div class="space-y-2">
      <Label for="totp_code">{{ t('auth.signIn.totp') }}</Label>
      <Input id="totp_code" v-model="form.session.totp_code" autocomplete="one-time-code" />
    </div>

    <label class="flex cursor-pointer items-center gap-2 text-sm">
      <Checkbox v-model="form.session.remember_me" />
      {{ t('auth.signIn.rememberMe') }}
    </label>

    <div class="flex flex-wrap items-center justify-between gap-3 pt-2">
      <Button type="submit" :disabled="form.processing">{{ t('common.signIn') }}</Button>
      <Link :href="routes.register" class="text-sm text-muted-foreground hover:text-foreground">
        {{ t('auth.signIn.createAccount') }}
      </Link>
    </div>
  </form>
</template>
