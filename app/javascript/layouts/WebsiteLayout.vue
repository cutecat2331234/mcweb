<script setup lang="ts">
import { computed, defineAsyncComponent } from 'vue'
import { Link, usePage } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import { Button, Space, Tag, TypographyText } from '@mcweb/ui'
import { routes } from '@/lib/routes'
import TemplateAssets from '@/components/portal/TemplateAssets.vue'
import { useActiveTemplate } from '@/lib/useActiveTemplate'
import { useFeatureFlags } from '@/lib/useFeatureFlags'
import { isBlogHref } from '@/lib/featureFlags'
import '@/styles/website.css'

interface NavItem {
  label: string
  href: string
}

interface PreviewContext {
  return_url: string
  edit_url: string
  label: string
  mode_label: string
}

const { t } = useI18n()
const page = usePage()
const DeveloperModeTools = defineAsyncComponent(
  () => import('@/components/portal/DeveloperModeTools.vue'),
)
const auth = computed(() => page.props.auth as { user: { username: string } | null })
const developerMode = computed(
  () =>
    (page.props.developer_mode ?? { enabled: false }) as {
      enabled: boolean
      profile?: string
      production_environment?: boolean
    },
)
const { activeTemplate, tokenStyle, websiteHeaderSlot, websiteFooterSlot } = useActiveTemplate()
const { features } = useFeatureFlags()
const frontendApplication = computed(() => (
  page.props.frontend_application ?? null
) as { id?: string } | null)
const previewContext = computed(() => (
  page.props.preview_context ?? null
) as PreviewContext | null)
const websitePreview = computed(() => (
  frontendApplication.value?.id === 'website_preview' && previewContext.value !== null
))

const websiteNav = computed(() => {
  const items = page.props.website_nav as NavItem[] | undefined
  const base = items?.length
    ? items
    : [
        { label: t('website.layout.home'), href: routes.home },
        { label: t('website.layout.about'), href: routes.page('about') },
        { label: t('website.layout.blog'), href: routes.blog },
      ]
  const pluginItems =
    (
      page.props.plugin_contributions as
        | { navigation?: { public?: NavItem[] } }
        | undefined
    )?.navigation?.public || []

  return [...base, ...pluginItems]
    .filter((item) => {
      if (!features.value.website_blog && isBlogHref(item.href)) return false
      return true
    })
    .filter(
      (item, index, collection) =>
        collection.findIndex((candidate) => candidate.href === item.href) === index,
    )
})

function isActive(href: string) {
  const current = page.url.split('?')[0]
  if (href === routes.home) return current === '/'
  return current === href
}


function leavePreview(path: string) {
  window.location.assign(path)
}
</script>

<template>
  <DeveloperModeTools v-if="developerMode.enabled" />
  <div
    v-if="websitePreview && previewContext"
    class="mc-preview-toolbar"
    :style="{
      position: 'sticky',
      top: 0,
      zIndex: 100,
      padding: '10px 16px',
      borderBottom: '1px solid var(--color-border-2)',
      background: 'var(--color-bg-2)',
    }"
  >
    <div :style="{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '16px' }">
      <Space align="center" :size="10">
        <Tag color="purple">{{ previewContext.mode_label }}</Tag>
        <TypographyText bold>{{ previewContext.label }}</TypographyText>
      </Space>
      <Space align="center" :size="8">
        <Button @click="leavePreview(previewContext.edit_url)">{{ t('common.edit') }}</Button>
        <Button type="primary" @click="leavePreview(previewContext.return_url)">
          {{ t('common.back') }}
        </Button>
      </Space>
    </div>
  </div>
  <div class="website-page" :style="tokenStyle">
    <TemplateAssets />

    <div
      v-if="developerMode.enabled"
      class="website-developer-mode"
      data-testid="developer-mode-banner"
      role="alert"
    >
      <div class="website-developer-mode__inner">
        <span class="website-developer-mode__label">{{ t('common.developerMode') }}</span>
        <span>{{ t('common.developerModeWarning') }}</span>
        <strong v-if="developerMode.production_environment">
          {{ t('common.developerModeProductionWarning') }}
        </strong>
      </div>
    </div>

    <div v-if="websiteHeaderSlot" v-html="websiteHeaderSlot" />
    <header v-else class="website-nav sticky top-0 z-50">
      <div class="mx-auto flex max-w-6xl items-center justify-between px-4 py-3.5">
        <Link :href="routes.home" class="website-brand flex items-center gap-2 no-underline">
          <img
            v-if="activeTemplate?.logoUrl"
            :src="activeTemplate.logoUrl"
            :alt="t('website.layout.logoAlt')"
            class="h-8 w-auto"
          >
          <span v-else class="website-brand-mark bg-gradient-to-br from-green-500/25 to-emerald-600/20 border-green-500/40">⛏</span>
          <span class="text-lg font-semibold tracking-tight text-white">McWeb</span>
        </Link>

        <nav class="hidden items-center gap-6 text-sm md:flex">
          <Link
            v-for="item in websiteNav"
            :key="item.href"
            :href="item.href"
            class="website-nav-link"
            :class="{ 'website-nav-link--active': isActive(item.href) }"
          >
            {{ item.label }}
          </Link>
        </nav>

        <div class="flex items-center gap-3 text-sm">
          <Link v-if="features.forum" :href="routes.forum" class="website-nav-link hidden sm:inline">{{ t('website.layout.forum') }}</Link>
          <Link v-if="features.store" :href="routes.store" class="website-nav-link hidden sm:inline">{{ t('website.layout.store') }}</Link>
          <Link
            v-if="features.forum && auth.user"
            :href="routes.forumUser(auth.user.username)"
            class="website-btn website-btn-ghost !px-4 !py-2 text-sm"
          >
            {{ auth.user.username }}
          </Link>
          <Link v-else :href="routes.signIn" class="website-btn website-btn-primary !px-4 !py-2 text-sm">
            {{ t('website.layout.enterApp') }}
          </Link>
        </div>
      </div>
      <div class="website-shimmer-line" />
    </header>

    <main>
      <slot />
    </main>

    <div v-if="websiteFooterSlot" v-html="websiteFooterSlot" />
    <footer v-else class="website-footer border-t border-green-500/15 py-12">
      <div class="mx-auto max-w-6xl px-4">
        <div class="grid gap-8 md:grid-cols-3">
          <div>
            <p class="font-semibold text-white">
              <span class="text-green-500">█</span> McWeb
            </p>
            <p class="mt-2 text-sm text-slate-400">{{ t('website.layout.tagline') }}</p>
          </div>
          <div>
            <p class="mb-3 text-sm font-medium text-slate-300">{{ t('website.layout.siteSection') }}</p>
            <div class="flex flex-col gap-2 text-sm">
              <Link v-for="item in websiteNav" :key="`f-${item.href}`" :href="item.href" class="website-nav-link w-fit">
                {{ item.label }}
              </Link>
            </div>
          </div>
          <div>
            <p class="mb-3 text-sm font-medium text-slate-300">{{ t('website.layout.appSection') }}</p>
            <div class="flex flex-col gap-2 text-sm">
              <Link v-if="features.forum" :href="routes.forum" class="website-nav-link w-fit">{{ t('website.layout.forum') }}</Link>
              <Link v-if="features.store" :href="routes.store" class="website-nav-link w-fit">{{ t('website.layout.store') }}</Link>
              <Link :href="routes.signIn" class="website-nav-link w-fit">{{ t('website.layout.signIn') }}</Link>
            </div>
          </div>
        </div>
        <p class="mt-10 border-t border-green-500/15 pt-6 text-center text-xs text-slate-500">
          {{ t('website.layout.copyright', { year: new Date().getFullYear() }) }}
        </p>
      </div>
    </footer>
  </div>
</template>
