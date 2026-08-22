<script setup lang="ts">
import { computed } from 'vue'
import { router, usePage } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import { IconCheck, IconLanguage } from '@arco-design/web-vue/es/icon'
import { normalizeAppLocale, preloadAppLocale, type AppLocale } from '@/lib/i18n'
import { csrfHeaders, readCsrfToken } from '@/lib/csrf'
import {
  beginAppLocalePreferenceTransaction,
  localePreferenceVisitCallbacks,
} from '@/lib/localePreference'
import { routes } from '@/lib/routes'

const page = usePage()
const { t } = useI18n()

const currentLocale = computed(() => normalizeAppLocale(page.props.locale))
const availableLocales = computed(() => {
  const raw = page.props.available_locales
  if (!Array.isArray(raw)) return ['zh-CN', 'en'] as AppLocale[]
  return raw.map((locale) => normalizeAppLocale(locale))
})

function localeLabel(locale: AppLocale) {
  return t(`locale.${locale}`)
}

async function switchLocale(value: string | number | Record<string, unknown>) {
  if (typeof value !== 'string') return
  const locale = normalizeAppLocale(value)
  if (locale === currentLocale.value) return
  await preloadAppLocale(locale)
  const transaction = beginAppLocalePreferenceTransaction(locale)

  try {
    router.patch(
      routes.locale,
      { locale, authenticity_token: readCsrfToken() },
      {
        preserveScroll: true,
        headers: csrfHeaders(),
        ...localePreferenceVisitCallbacks(transaction),
      },
    )
  } catch (error) {
    transaction.rollback()
    throw error
  }
}
</script>

<template>
  <a-dropdown trigger="click" @select="switchLocale">
    <a-button type="text" shape="circle" :aria-label="t('locale.label')">
      <template #icon><icon-language /></template>
    </a-button>
    <template #content>
      <a-doption
        v-for="locale in availableLocales"
        :key="locale"
        :value="locale"
      >
        <template #icon>
          <icon-check v-if="locale === currentLocale" />
        </template>
        {{ localeLabel(locale) }}
      </a-doption>
    </template>
  </a-dropdown>
</template>
