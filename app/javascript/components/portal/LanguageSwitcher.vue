<script setup lang="ts">
import { computed } from 'vue'
import { usePage } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import { Button, Doption, Dropdown } from '@mcweb/ui'
import { IconCheck, IconLanguage } from '@arco-design/web-vue/es/icon'

import { documentFrontendApplicationId } from '@/lib/frontendApplications'
import { normalizeAppLocale, preloadAppLocale, type AppLocale } from '@/lib/i18n'
import { beginAppLocalePreferenceTransaction } from '@/lib/localePreference'
import { routes } from '@/lib/routes'
import { performSharedAction } from '@/lib/sharedAction'
import { navigateFrontendDocument } from '@/lib/applicationNavigation'
import { confirmUnsavedNavigation } from '@/lib/unsavedForms'

const page = usePage()
const { t } = useI18n()
const currentLocale = computed(() => normalizeAppLocale(page.props.locale))
const availableLocales = computed(() => {
  const raw = page.props.available_locales
  if (!Array.isArray(raw)) return ['zh-CN', 'en'] as AppLocale[]
  return raw.map((locale) => normalizeAppLocale(locale))
})

async function switchLocale(value: string | number | Record<string, unknown>) {
  if (typeof value !== 'string') return
  const locale = normalizeAppLocale(value)
  if (locale === currentLocale.value) return
  if (!confirmUnsavedNavigation()) return
  await preloadAppLocale(locale)
  const transaction = beginAppLocalePreferenceTransaction(locale)
  try {
    await performSharedAction(documentFrontendApplicationId(), routes.locale, {
      method: 'PATCH',
      data: { locale },
    })
    transaction.commit()
    navigateFrontendDocument(window.location.href)
  } catch (error) {
    transaction.rollback()
    throw error
  }
}
</script>

<template>
  <Dropdown trigger="click" @select="switchLocale">
    <Button type="text" shape="circle" :aria-label="t('locale.label')">
      <template #icon><IconLanguage /></template>
    </Button>
    <template #content>
      <Doption v-for="locale in availableLocales" :key="locale" :value="locale">
        <template #icon><IconCheck v-if="locale === currentLocale" /></template>
        {{ t(`locale.${locale}`) }}
      </Doption>
    </template>
  </Dropdown>
</template>
