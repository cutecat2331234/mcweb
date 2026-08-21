<script setup lang="ts">
import { computed } from 'vue'
import { Link, usePage } from '@inertiajs/vue3'
import { Moon, Sun } from '@lucide/vue'
import { useI18n } from 'vue-i18n'
import Button from '@/components/ui/Button.vue'
import DeveloperModeTools from '@/components/portal/DeveloperModeTools.vue'
import FlashMessages from '@/components/portal/FlashMessages.vue'
import LanguageSwitcher from '@/components/portal/LanguageSwitcher.vue'
import TemplateAssets from '@/components/portal/TemplateAssets.vue'
import { routes } from '@/lib/routes'
import { useActiveTemplate } from '@/lib/useActiveTemplate'
import { useFeatureFlags } from '@/lib/useFeatureFlags'
import { useTheme } from '@/lib/useTheme'

const page = usePage()
const { t } = useI18n()
const { activeTemplate, tokenStyle } = useActiveTemplate()
const { features } = useFeatureFlags()
const { isDark, toggleTheme } = useTheme()
const developerMode = computed(
  () =>
    (page.props.developer_mode ?? { enabled: false }) as {
      enabled: boolean
      runtime_profile?: string
      production_environment?: boolean
    },
)
</script>

<template>
  <DeveloperModeTools />
  <div class="min-h-dvh bg-background text-foreground" :style="tokenStyle">
    <TemplateAssets :include-css="false" />

    <header class="sticky top-0 z-30 border-b bg-background/95 backdrop-blur">
      <div class="mx-auto flex h-16 max-w-6xl items-center gap-3 px-4 sm:px-6">
        <Link :href="routes.home" class="flex min-w-0 items-center gap-2 no-underline">
          <img
            v-if="activeTemplate?.logoUrl"
            :src="activeTemplate.logoUrl"
            alt=""
            class="h-8 w-auto"
          >
          <span class="truncate text-base font-semibold">{{ t('portal.brand') }}</span>
        </Link>

        <nav class="ml-auto hidden items-center gap-1 sm:flex" :aria-label="t('common.navigation')">
          <Button v-if="features.forum" as-child variant="ghost" size="sm">
            <Link :href="routes.forum">{{ t('website.layout.forum') }}</Link>
          </Button>
          <Button v-if="features.store" as-child variant="ghost" size="sm">
            <Link :href="routes.store">{{ t('website.layout.store') }}</Link>
          </Button>
        </nav>

        <LanguageSwitcher />
        <Button
          variant="ghost"
          size="icon"
          type="button"
          :aria-label="t('common.toggleTheme')"
          @click="toggleTheme"
        >
          <Sun v-if="isDark" class="h-4 w-4" />
          <Moon v-else class="h-4 w-4" />
        </Button>
      </div>
    </header>

    <div
      v-if="developerMode.enabled"
      class="border-b border-amber-500/30 bg-amber-500/10 px-4 py-2 text-center text-sm text-amber-950 dark:text-amber-100"
      data-testid="developer-mode-banner"
    >
      {{ t('common.developerMode') }}
      <span v-if="developerMode.runtime_profile"> · {{ developerMode.runtime_profile }}</span>
    </div>

    <main class="mx-auto flex w-full max-w-6xl justify-center px-4 py-8 sm:px-6 sm:py-12">
      <section
        class="w-full max-w-lg rounded-2xl border border-border/80 bg-card p-5 text-card-foreground shadow-sm sm:p-8"
        data-testid="auth-surface"
      >
        <FlashMessages />
        <slot />
      </section>
    </main>
  </div>
</template>
