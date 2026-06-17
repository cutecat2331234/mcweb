<script setup lang="ts">
import { computed } from 'vue'
import { Link, usePage } from '@inertiajs/vue3'
import { routes } from '@/lib/routes'
import TemplateAssets from '@/components/portal/TemplateAssets.vue'
import { useActiveTemplate } from '@/lib/useActiveTemplate'
import '@/styles/website.css'

const page = usePage()
const auth = computed(() => page.props.auth as { user: { username: string } | null })
const { activeTemplate, tokenStyle, websiteHeaderSlot, websiteFooterSlot } = useActiveTemplate()
</script>

<template>
  <div class="website-page" :style="tokenStyle">
    <TemplateAssets />

    <div v-if="websiteHeaderSlot" v-html="websiteHeaderSlot" />
    <header v-else class="website-nav sticky top-0 z-50">
      <div class="mx-auto flex max-w-6xl items-center justify-between px-4 py-4">
        <Link :href="routes.home" class="flex items-center gap-2 text-lg font-semibold text-white no-underline">
          <img v-if="activeTemplate?.logoUrl" :src="activeTemplate.logoUrl" alt="Logo" class="h-8 w-auto">
          <span>Mcweb</span>
        </Link>
        <nav class="flex items-center gap-5 text-sm">
          <Link :href="routes.home" class="website-nav-link">首页</Link>
          <Link :href="routes.forum" class="website-nav-link">论坛</Link>
          <Link :href="routes.store" class="website-nav-link">商城</Link>
          <Link
            v-if="auth.user"
            :href="routes.forum"
            class="website-nav-link"
          >
            {{ auth.user.username }}
          </Link>
          <Link v-else :href="routes.signIn" class="website-nav-link">登录</Link>
        </nav>
      </div>
    </header>

    <main>
      <slot />
    </main>

    <div v-if="websiteFooterSlot" v-html="websiteFooterSlot" />
    <footer v-else class="border-t border-white/10 py-10 text-center text-sm text-slate-400">
      <p>Mcweb — 面向 Minecraft 服主的开源社区与商城系统</p>
    </footer>
  </div>
</template>
