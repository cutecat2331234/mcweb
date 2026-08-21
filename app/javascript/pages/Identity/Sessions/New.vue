<script setup lang="ts">
import { computed, nextTick, ref, watch } from 'vue'
import { Link, useForm, usePage } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import {
  Alert,
  Button,
  Checkbox,
  Divider,
  Form,
  FormItem,
  Input,
  InputPassword,
  PageHeader,
  Space,
} from '@mcweb/ui'
import AuthLayout from '@/layouts/AuthLayout.vue'
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
  <Space direction="vertical" fill size="large">
    <PageHeader
      :show-back="false"
      :title="t('auth.signIn.title')"
      :subtitle="t('auth.signIn.subtitle')"
    />

    <div v-if="loginError" ref="errorSummary" tabindex="-1">
      <Alert type="error" show-icon :title="t('auth.signIn.failed')">
        {{ loginError }}
      </Alert>
    </div>

    <Form
      :model="form.session"
      layout="vertical"
      size="large"
      @submit="submit"
    >
      <input type="hidden" name="authenticity_token" :value="String(page.props.csrf_token || readCsrfToken())" />
      <FormItem
        field="email"
        :label="t('auth.signIn.email')"
        :help="form.errors['session.email']"
        :validate-status="form.errors['session.email'] ? 'error' : undefined"
        required
      >
        <Input
          id="email"
          v-model="form.session.email"
          name="session[email]"
          type="email"
          autocomplete="email"
          required
          autofocus
          allow-clear
          :aria-invalid="!!form.errors['session.email']"
        />
      </FormItem>

      <FormItem
        field="password"
        :label="t('auth.signIn.password')"
        :help="form.errors['session.password']"
        :validate-status="form.errors['session.password'] ? 'error' : undefined"
        required
      >
        <InputPassword
          id="password"
          v-model="form.session.password"
          name="session[password]"
          autocomplete="current-password"
          required
          :aria-invalid="!!form.errors['session.password']"
        />
      </FormItem>

      <FormItem field="remember_me" hide-label>
        <Checkbox v-model="form.session.remember_me">
          {{ t('auth.signIn.rememberMe') }}
        </Checkbox>
      </FormItem>

      <Button
        type="primary"
        html-type="submit"
        size="large"
        long
        :loading="form.processing"
        :disabled="form.processing"
      >
        {{ t('common.signIn') }}
      </Button>

      <Divider />

      <Space direction="vertical" fill :size="8" align="center">
        <Link :href="routes.register" class="text-muted-foreground hover:text-foreground">
          {{ t('auth.signIn.createAccount') }}
        </Link>
        <Link :href="routes.resendVerification" class="text-muted-foreground hover:text-foreground">
          {{ t('identity.resendVerification.submit') }}
        </Link>
      </Space>
    </Form>
  </Space>
</template>
