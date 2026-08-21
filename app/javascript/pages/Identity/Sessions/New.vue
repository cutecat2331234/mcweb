<script setup lang="ts">
import { computed, nextTick, ref, watch } from 'vue'
import { Link, useForm, usePage } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AuthLayout from '@/layouts/AuthLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Checkbox from '@/components/ui/Checkbox.vue'
import Alert from '@/components/ui/Alert.vue'
import { routes } from '@/lib/routes'
import { csrfHeaders, readCsrfToken } from '@/lib/csrf'

defineOptions({ layout: AuthLayout })

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
    remember_me: false,
  },
})

const loginError = computed(() => {
  if (form.errors.base) return form.errors.base
  if (props.login_error) return props.login_error
  const pageErrors = page.props.errors as Record<string, string> | undefined
  return pageErrors?.base || ''
})

const errorSummary = ref<HTMLElement | null>(null)

watch(loginError, async (message) => {
  if (!message) return
  await nextTick()
  errorSummary.value?.focus()
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
  <PageHeader density="compact" :title="t('auth.signIn.title')" :subtitle="t('auth.signIn.subtitle')" />

  <div v-if="loginError" ref="errorSummary" class="mb-4 max-w-md" tabindex="-1">
    <Alert variant="destructive" :title="t('auth.signIn.failed')">
      {{ loginError }}
    </Alert>
  </div>

  <form
    class="w-full space-y-5"
    method="post"
    :action="routes.identitySession"
    @submit.prevent="submit"
  >
    <input type="hidden" name="authenticity_token" :value="String(page.props.csrf_token || readCsrfToken())" />
    <div class="space-y-2">
      <Label for="email">{{ t('auth.signIn.email') }}</Label>
      <Input
        id="email"
        v-model="form.session.email"
        name="session[email]"
        type="email"
        autocomplete="email"
        density="comfortable"
        required
        autofocus
        :aria-invalid="!!form.errors['session.email']"
        :aria-describedby="form.errors['session.email'] ? 'sign-in-email-error' : undefined"
      />
      <p v-if="form.errors['session.email']" id="sign-in-email-error" class="text-sm leading-5 text-destructive" role="alert">{{ form.errors['session.email'] }}</p>
    </div>

    <div class="space-y-2">
      <Label for="password">{{ t('auth.signIn.password') }}</Label>
      <Input
        id="password"
        v-model="form.session.password"
        name="session[password]"
        type="password"
        autocomplete="current-password"
        density="comfortable"
        required
        :aria-invalid="!!form.errors['session.password']"
        :aria-describedby="form.errors['session.password'] ? 'sign-in-password-error' : undefined"
      />
      <p v-if="form.errors['session.password']" id="sign-in-password-error" class="text-sm leading-5 text-destructive" role="alert">{{ form.errors['session.password'] }}</p>
    </div>

    <label class="flex min-h-11 cursor-pointer items-center gap-2 text-sm leading-5">
      <Checkbox v-model="form.session.remember_me" />
      {{ t('auth.signIn.rememberMe') }}
    </label>

    <div class="flex flex-col items-stretch gap-4 pt-1 sm:flex-row sm:items-center sm:justify-between">
      <Button class="w-full sm:w-auto" size="comfortable" type="submit" :disabled="form.processing">{{ t('common.signIn') }}</Button>
      <div class="flex flex-col items-start gap-2 text-sm leading-5 sm:items-end">
        <Link :href="routes.register" class="text-muted-foreground hover:text-foreground">
          {{ t('auth.signIn.createAccount') }}
        </Link>
        <Link :href="routes.resendVerification" class="text-muted-foreground hover:text-foreground">
          {{ t('identity.resendVerification.submit') }}
        </Link>
      </div>
    </div>
  </form>
</template>
