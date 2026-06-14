<script setup lang="ts">
import { computed } from 'vue'
import { Link, usePage } from '@inertiajs/vue3'
import { Moon, Sun, Bell } from '@lucide/vue'
import { routes } from '@/lib/routes'
import FlashMessages from '@/components/portal/FlashMessages.vue'
import Button from '@/components/ui/Button.vue'
import Badge from '@/components/ui/Badge.vue'

const page = usePage()
const auth = computed(() => page.props.auth as { user: { username: string } | null })
const notifications = computed(() => page.props.notifications as { unread_count: number; url: string } | undefined)

const isDark = computed(() => document.documentElement.classList.contains('dark'))

function toggleTheme() {
  const next = isDark.value ? 'light' : 'dark'
  document.documentElement.classList.toggle('dark', next === 'dark')
  localStorage.setItem('mc-theme', next)
}
</script>

<template>
  <div class="min-h-dvh bg-background">
    <header class="sticky top-0 z-40 border-b bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/80">
      <div class="mx-auto flex h-14 max-w-6xl items-center justify-between px-4">
        <div class="flex items-center gap-6">
          <Link :href="routes.home" class="text-sm font-semibold tracking-tight no-underline text-foreground">
            Mcweb
          </Link>
          <nav class="hidden items-center gap-4 text-sm text-muted-foreground md:flex">
            <Link :href="routes.forum" class="hover:text-foreground transition-colors">论坛</Link>
            <Link :href="routes.forumLatest" class="hover:text-foreground transition-colors">最新</Link>
            <Link :href="routes.forumSearch" class="hover:text-foreground transition-colors">搜索</Link>
            <Link :href="routes.forumTags" class="hover:text-foreground transition-colors">标签</Link>
            <Link v-if="auth.user" :href="routes.forumWatching" class="hover:text-foreground transition-colors">关注</Link>
            <Link v-if="auth.user" :href="routes.forumBookmarks" class="hover:text-foreground transition-colors">书签</Link>
            <Link v-if="auth.user" :href="routes.forumMessages" class="hover:text-foreground transition-colors">私信</Link>
            <Link :href="routes.store" class="hover:text-foreground transition-colors">商城</Link>
            <Link v-if="auth.user" :href="routes.storeWishlist" class="hover:text-foreground transition-colors">心愿单</Link>
          </nav>
        </div>

        <div class="flex items-center gap-2">
          <Button variant="ghost" size="icon" type="button" aria-label="切换主题" @click="toggleTheme">
            <Sun v-if="isDark" class="h-4 w-4" />
            <Moon v-else class="h-4 w-4" />
          </Button>
          <Button v-if="auth.user && notifications" as-child variant="ghost" size="icon" class="relative">
            <Link :href="notifications.url" aria-label="通知">
              <Bell class="h-4 w-4" />
              <Badge
                v-if="notifications.unread_count > 0"
                variant="danger"
                class="absolute -right-1 -top-1 h-4 min-w-4 px-1 text-[10px]"
              >
                {{ notifications.unread_count > 99 ? '99+' : notifications.unread_count }}
              </Badge>
            </Link>
          </Button>
          <div class="mx-1 h-6 w-px bg-border" />
          <Link v-if="auth.user" :href="routes.forumUser(auth.user.username)" class="text-sm text-muted-foreground hover:text-foreground">
            {{ auth.user.username }}
          </Link>
          <Button v-else as-child variant="outline" size="sm">
            <Link :href="routes.signIn">登录</Link>
          </Button>
        </div>
      </div>
    </header>

    <main class="mx-auto max-w-6xl px-4 py-6">
      <FlashMessages />
      <slot />
    </main>
  </div>
</template>
