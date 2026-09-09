<script setup lang="ts">
import { computed, defineAsyncComponent } from 'vue'
import { usePage } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import {
  Button,
  Card,
  Layout,
  LayoutContent,
  LayoutHeader,
  Space,
  TypographyText,
} from '@mcweb/ui'
import { IconMoon, IconSun } from '@arco-design/web-vue/es/icon'
import LanguageSwitcher from '@/components/portal/LanguageSwitcher.vue'
import TemplateAssets from '@/components/portal/TemplateAssets.vue'
import { usePortalApplicationStatusSurfaces } from '@/lib/applicationStatusSurfaces'
import { routes } from '@/lib/routes'
import { useActiveTemplate } from '@/lib/useActiveTemplate'
import { useFeatureFlags } from '@/lib/useFeatureFlags'
import { useTheme } from '@/lib/useTheme'

const page = usePage()
const { t } = useI18n()
const { activeTemplate, tokenStyle } = useActiveTemplate()
const { features } = useFeatureFlags()
const { isDark, toggleTheme } = useTheme()
const { developerModeBanner, flashMessages } = usePortalApplicationStatusSurfaces()
const DeveloperModeTools = __MCWEB_DEVELOPER_BUILD__
  ? defineAsyncComponent(() => import('@/components/portal/DeveloperModeTools.vue'))
  : null
const flash = computed(() => page.props.flash as {
  notice?: string
  alert?: string
} | undefined)
const hasFlashMessages = computed(() => Boolean(flash.value?.notice || flash.value?.alert))
const developerMode = computed(
  () =>
    (page.props.developer_mode ?? { enabled: false }) as {
      enabled: boolean
      runtime_profile?: string
      production_environment?: boolean
    },
)
const developerModeMessage = computed(() => [
  t('common.developerModeWarning'),
  developerMode.value.production_environment
    ? t('common.developerModeProductionWarning')
    : null,
  developerMode.value.runtime_profile || null,
].filter(Boolean).join(' · '))
</script>

<template>
  <component
    :is="DeveloperModeTools"
    v-if="DeveloperModeTools && developerMode.enabled"
  />
  <Layout class="min-h-dvh bg-background text-foreground" :style="tokenStyle">
    <TemplateAssets :include-css="false" />

    <LayoutHeader class="sticky top-0 z-30 border-b bg-background/95 backdrop-blur">
      <div class="mx-auto flex h-16 max-w-6xl items-center gap-3 px-4 sm:px-6">
        <a :href="routes.home" class="flex min-w-0 items-center gap-2 no-underline">
          <img
            v-if="activeTemplate?.logoUrl"
            :src="activeTemplate.logoUrl"
            alt=""
            class="h-8 w-auto"
          >
          <TypographyText class="truncate" bold>{{ t('portal.brand') }}</TypographyText>
        </a>

        <nav class="ml-auto hidden sm:block" :aria-label="t('common.navigation')">
          <Space size="mini">
            <Button v-if="features.forum" type="text" size="small" :href="routes.forum">
              {{ t('nav.forum') }}
            </Button>
            <Button v-if="features.store" type="text" size="small" :href="routes.store">
              {{ t('nav.store') }}
            </Button>
          </Space>
        </nav>

        <LanguageSwitcher />
        <Button
          type="text"
          shape="circle"
          html-type="button"
          :aria-label="t('common.toggleTheme')"
          @click="toggleTheme"
        >
          <template #icon>
            <IconSun v-if="isDark" />
            <IconMoon v-else />
          </template>
        </Button>
      </div>
    </LayoutHeader>

    <component
      :is="developerModeBanner"
      v-if="developerMode.enabled && developerModeBanner"
      :title="t('common.developerMode')"
      :message="developerModeMessage"
    />

    <LayoutContent>
      <main class="mx-auto flex w-full max-w-6xl justify-center px-4 py-8 sm:px-6 sm:py-12">
        <Card
          class="w-full max-w-lg"
          :bordered="true"
          :body-style="{ padding: '24px' }"
          data-testid="auth-surface"
        >
          <component :is="flashMessages" v-if="hasFlashMessages && flashMessages" />
          <slot />
        </Card>
      </main>
    </LayoutContent>
  </Layout>
</template>
