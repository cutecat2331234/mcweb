<script setup lang="ts">
import { computed, watch } from 'vue'
import { Link, useForm, usePage } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Alert from '@/components/ui/Alert.vue'
import Select from '@/components/ui/Select.vue'
import { routes } from '@/lib/routes'
import { csrfHeaders, readCsrfToken } from '@/lib/csrf'
import { normalizeAppLocale, type AppLocale } from '@/lib/i18n'

defineOptions({ layout: PortalLayout })

const props = defineProps<{
  form_errors?: Record<string, string>
}>()

const page = usePage()
const { t } = useI18n()

const availableLocales = computed(() => {
  const raw = page.props.available_locales
  if (!Array.isArray(raw)) return [ 'zh-CN', 'en' ] as AppLocale[]
  return raw.map((locale) => normalizeAppLocale(locale))
})

const form = useForm({
  registration: {
    email: '',
    username: '',
    display_name: '',
    password: '',
    locale: normalizeAppLocale(page.props.locale),
    time_zone: 'Asia/Shanghai',
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

const formError = computed(() => {
  if (form.errors.base) return form.errors.base
  return props.form_errors?.base || ''
})

function fieldError(key: string) {
  return form.errors[`registration.${key}` as keyof typeof form.errors] || props.form_errors?.[`registration.${key}`] || ''
}

function submit() {
  const token = String(page.props.csrf_token || readCsrfToken())
  form
    .transform((data) => ({ ...data, authenticity_token: token }))
    .post(routes.register, {
      preserveScroll: true,
      headers: csrfHeaders(),
    })
}
</script>

<template>
  <PageHeader :title="t('auth.register.title')" :subtitle="t('auth.register.subtitle')" />

  <Alert v-if="formError" variant="destructive" :title="t('auth.register.failed')" class="mb-4 max-w-md">
    {{ formError }}
  </Alert>

  <form class="max-w-md space-y-4" @submit.prevent="submit">
    <div class="space-y-2">
      <Label for="email">{{ t('auth.register.email') }}</Label>
      <Input id="email" v-model="form.registration.email" type="email" required autofocus autocomplete="email" />
      <p v-if="fieldError('email')" class="text-sm text-destructive">{{ fieldError('email') }}</p>
    </div>
    <div class="space-y-2">
      <Label for="username">{{ t('auth.register.username') }}</Label>
      <Input id="username" v-model="form.registration.username" required autocomplete="username" />
      <p v-if="fieldError('username')" class="text-sm text-destructive">{{ fieldError('username') }}</p>
    </div>
    <div class="space-y-2">
      <Label for="display_name">{{ t('auth.register.displayName') }}</Label>
      <Input id="display_name" v-model="form.registration.display_name" autocomplete="name" />
    </div>
    <div class="space-y-2">
      <Label for="password">{{ t('auth.register.password') }}</Label>
      <Input id="password" v-model="form.registration.password" type="password" required autocomplete="new-password" />
      <p v-if="fieldError('password')" class="text-sm text-destructive">{{ fieldError('password') }}</p>
    </div>
    <div class="space-y-2">
      <Label for="locale">{{ t('auth.register.locale') }}</Label>
      <Select id="locale" v-model="form.registration.locale">
        <option v-for="locale in availableLocales" :key="locale" :value="locale">
          {{ t(`locale.${locale}`) }}
        </option>
      </Select>
    </div>
    <div class="flex flex-wrap items-center justify-between gap-3 pt-2">
      <Button type="submit" :disabled="form.processing">{{ t('common.register') }}</Button>
      <Link :href="routes.signIn" class="text-sm text-muted-foreground hover:text-foreground">{{ t('auth.register.hasAccount') }}</Link>
    </div>
  </form>
</template>
