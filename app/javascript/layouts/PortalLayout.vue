<script setup lang="ts">
import { computed } from 'vue'
import { Link, usePage } from '@inertiajs/vue3'
import { Moon, Sun } from '@lucide/vue'
import { routes } from '@/lib/routes'
import FlashMessages from '@/components/portal/FlashMessages.vue'
import Button from '@/components/ui/Button.vue'

const page = usePage()
const auth = computed(() => page.props.auth as { user: { username: string } | null })

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
            <Link :href="routes.store" class="hover:text-foreground transition-colors">商城</Link>
          </nav>
        </div>

        <div class="flex items-center gap-2">
          <Button variant="ghost" size="icon" type="button" aria-label="切换主题" @click="toggleTheme">
            <Sun v-if="isDark" class="h-4 w-4" />
            <Moon v-else class="h-4 w-4" />
          </Button>
          <div class="mx-1 h-6 w-px bg-border" />
          <Link v-if="auth.user" :href="routes.forum" class="text-sm text-muted-foreground hover:text-foreground">
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
