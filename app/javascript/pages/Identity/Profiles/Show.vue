<script setup lang="ts">
import { computed, watch } from 'vue'
import { router, useForm, usePage } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import {
  Alert,
  Button,
  Card,
  Descriptions,
  DescriptionsItem,
  Form,
  FormItem,
  Input,
  Option,
  PageHeader,
  Select,
  Space,
  TypographyParagraph,
} from '@mcweb/ui'
import PortalLayout from '@/layouts/PortalLayout.vue'
import { normalizeAppLocale, preloadAppLocale, type AppLocale } from '@/lib/i18n'
import { localeRequestHeaders, writeSharedAppLocale } from '@/lib/localePreference'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const props = defineProps<{
  profile: {
    username: string
    email: string
    display_name: string | null
    locale: string
  }
  form_errors?: Record<string, string> | null
}>()

const page = usePage()
const { t } = useI18n()

const availableLocales = computed(() => {
  const locales = page.props.available_locales
  if (!Array.isArray(locales)) return [ 'zh-CN', 'en' ] as AppLocale[]
  return [...new Set(locales.map((value) => normalizeAppLocale(value)))]
})

const form = useForm({
  profile: {
    display_name: props.profile.display_name || '',
    locale: normalizeAppLocale(props.profile.locale),
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

function fieldError(field: 'display_name' | 'locale') {
  const key = `profile.${field}`
  return form.errors[key as keyof typeof form.errors] || props.form_errors?.[key] || ''
}

function currentPersistedLocale(): AppLocale {
  const auth = page.props.auth as { user?: { locale?: unknown } | null } | undefined
  return normalizeAppLocale(auth?.user?.locale ?? page.props.locale)
}

async function submit() {
  const selectedLocale = normalizeAppLocale(form.profile.locale)
  const previousLocale = currentPersistedLocale()
  form.profile.locale = selectedLocale
  await preloadAppLocale(selectedLocale)
  form.patch(routes.identityProfile, {
    preserveScroll: true,
    headers: localeRequestHeaders(selectedLocale),
    onSuccess: (nextPage) => {
      const responseErrors = nextPage.props.form_errors
      const auth = nextPage.props.auth as { user?: { locale?: unknown } | null } | undefined
      const persistedLocale = typeof auth?.user?.locale === 'string'
        ? normalizeAppLocale(auth.user.locale)
        : null
      if (
        (responseErrors && Object.keys(responseErrors as object).length > 0) ||
        persistedLocale !== selectedLocale
      ) {
        writeSharedAppLocale(previousLocale)
        return
      }

      writeSharedAppLocale(selectedLocale)
      form.defaults({
        profile: {
          display_name: form.profile.display_name,
          locale: selectedLocale,
        },
      })
    },
    onError: () => writeSharedAppLocale(previousLocale),
    onCancel: () => writeSharedAppLocale(previousLocale),
  })
}
</script>

<template>
  <Space direction="vertical" fill size="large">
    <PageHeader
      :title="t('identity.profile.title')"
      :subtitle="t('identity.profile.subtitle')"
      @back="router.visit(routes.account)"
    />

    <Card :title="t('identity.profile.accountIdentity')" :bordered="true">
      <Descriptions :column="1" size="medium">
        <DescriptionsItem :label="t('identity.profile.username')">
          {{ profile.username }}
        </DescriptionsItem>
        <DescriptionsItem :label="t('identity.profile.email')">
          {{ profile.email }}
        </DescriptionsItem>
      </Descriptions>
      <TypographyParagraph type="secondary" class="!mb-0">
        {{ t('identity.profile.readOnlyHint') }}
      </TypographyParagraph>
    </Card>

    <Card :title="t('identity.profile.editableDetails')" :bordered="true">
      <Alert v-if="baseError" type="error" show-icon class="mb-4">
        {{ baseError }}
      </Alert>

      <Form :model="form.profile" layout="vertical" class="max-w-xl" @submit="submit">
        <FormItem
          field="display_name"
          :label="t('identity.profile.displayName')"
          :help="fieldError('display_name') || t('identity.profile.displayNameHint')"
          :validate-status="fieldError('display_name') ? 'error' : undefined"
        >
          <Input
            v-model="form.profile.display_name"
            :placeholder="t('identity.profile.displayNamePlaceholder')"
            :max-length="64"
            show-word-limit
            allow-clear
            autocomplete="name"
          />
        </FormItem>

        <FormItem
          field="locale"
          :label="t('identity.profile.language')"
          :help="fieldError('locale') || t('identity.profile.languageHint')"
          :validate-status="fieldError('locale') ? 'error' : undefined"
        >
          <Select v-model="form.profile.locale">
            <Option v-for="availableLocale in availableLocales" :key="availableLocale" :value="availableLocale">
              {{ t(`locale.${availableLocale}`) }}
            </Option>
          </Select>
        </FormItem>

        <Button type="primary" html-type="submit" :loading="form.processing" :disabled="form.processing">
          {{ t('identity.profile.save') }}
        </Button>
      </Form>
    </Card>
  </Space>
</template>
