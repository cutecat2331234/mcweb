<script setup lang="ts">
import { computed } from 'vue'
import { Link, usePage } from '@inertiajs/vue3'
import { routes, appPrefix } from '@/lib/routes'
import TemplateAssets from '@/components/portal/TemplateAssets.vue'
import { useActiveTemplate } from '@/lib/useActiveTemplate'
import { useFeatureFlags } from '@/lib/useFeatureFlags'
import { isBlogHref } from '@/lib/featureFlags'
import '@/styles/website.css'

interface NavItem {
  label: string
  href: string
}

const page = usePage()
const auth = computed(() => page.props.auth as { user: { username: string } | null })
const { activeTemplate, tokenStyle, websiteHeaderSlot, websiteFooterSlot } = useActiveTemplate()
const { features } = useFeatureFlags()

const websiteNav = computed(() => {
  const items = page.props.website_nav as NavItem[] | undefined
  const base = items?.length
    ? items
    : [
        { label: '首页', href: routes.home },
        { label: '关于', href: routes.page('about') },
        { label: '动态', href: routes.blog },
      ]

  return base.filter((item) => {
    if (!features.value.website_blog && isBlogHref(item.href)) return false
    return true
  })
})

function isActive(href: string) {
  const current = page.url.split('?')[0]
  if (href === routes.home) return current === '/'
  return current === href
}
</script>

<template>
  <div class="website-page" :style="tokenStyle">
    <TemplateAssets />

    <div v-if="websiteHeaderSlot" v-html="websiteHeaderSlot" />
    <header v-else class="website-nav sticky top-0 z-50">
      <div class="mx-auto flex max-w-6xl items-center justify-between px-4 py-3.5">
        <Link :href="routes.home" class="website-brand flex items-center gap-2 no-underline">
          <img v-if="activeTemplate?.logoUrl" :src="activeTemplate.logoUrl" alt="Logo" class="h-8 w-auto">
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
          <Link v-if="features.forum" :href="routes.forum" class="website-nav-link hidden sm:inline">论坛</Link>
          <Link v-if="features.store" :href="routes.store" class="website-nav-link hidden sm:inline">商城</Link>
          <Link
            v-if="features.forum && auth.user"
            :href="routes.forumUser(auth.user.username)"
            class="website-btn website-btn-ghost !px-4 !py-2 text-sm"
          >
            {{ auth.user.username }}
          </Link>
          <Link v-else :href="routes.signIn" class="website-btn website-btn-primary !px-4 !py-2 text-sm">
            进入应用 →
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
            <p class="mt-2 text-sm text-slate-400">面向 Minecraft 服主的开源社区与商城系统</p>
          </div>
          <div>
            <p class="mb-3 text-sm font-medium text-slate-300">官网</p>
            <div class="flex flex-col gap-2 text-sm">
              <Link v-for="item in websiteNav" :key="`f-${item.href}`" :href="item.href" class="website-nav-link w-fit">
                {{ item.label }}
              </Link>
            </div>
          </div>
          <div>
            <p class="mb-3 text-sm font-medium text-slate-300">应用中心</p>
            <div class="flex flex-col gap-2 text-sm">
              <Link v-if="features.forum" :href="routes.forum" class="website-nav-link w-fit">论坛</Link>
              <Link v-if="features.store" :href="routes.store" class="website-nav-link w-fit">商城</Link>
              <Link :href="routes.signIn" class="website-nav-link w-fit">登录</Link>
            </div>
          </div>
        </div>
        <p class="mt-10 border-t border-green-500/15 pt-6 text-center text-xs text-slate-500">
          ▣ {{ new Date().getFullYear() }} McWeb · 用户功能位于 {{ appPrefix }} 模块
        </p>
      </div>
    </footer>
  </div>
</template>
