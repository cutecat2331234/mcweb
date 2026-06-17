<script setup lang="ts">
import { computed, ref } from 'vue'
import { Link, usePage } from '@inertiajs/vue3'
import { Moon, Sun, Bell, Mail, ShoppingCart } from '@lucide/vue'
import { routes } from '@/lib/routes'
import FlashMessages from '@/components/portal/FlashMessages.vue'
import ForumShortcuts from '@/components/portal/ForumShortcuts.vue'
import PortalSubnav from '@/components/portal/PortalSubnav.vue'
import TemplateAssets from '@/components/portal/TemplateAssets.vue'
import Button from '@/components/ui/Button.vue'
import Badge from '@/components/ui/Badge.vue'
import { useActiveTemplate } from '@/lib/useActiveTemplate'

const page = usePage()
const auth = computed(() => page.props.auth as { user: { username: string } | null })
const notifications = computed(() => page.props.notifications as { unread_count: number; url: string } | undefined)
const forumUnread = computed(() => page.props.forum_unread as { count: number; url: string } | undefined)
const forumAssigned = computed(() => page.props.forum_assigned as { count: number; url: string } | undefined)
const messagesUnread = computed(() => page.props.messages_unread as { count: number; url: string } | undefined)
const cart = computed(() => page.props.cart as { count: number; url: string } | undefined)
const globalAnnouncements = computed(() => page.props.global_announcements as Array<{ title: string; url: string; id: string }> | undefined)
const { activeTemplate, tokenStyle, portalHeaderExtraSlot } = useActiveTemplate()

const dismissedLocal = ref<string[]>(loadDismissedLocal())

function loadDismissedLocal(): string[] {
  try {
    return JSON.parse(localStorage.getItem('mc-dismissed-announcements') || '[]')
  } catch {
    return []
  }
}

const visibleAnnouncements = computed(() => {
  const items = globalAnnouncements.value || []
  return items.filter((item) => !dismissedLocal.value.includes(item.id))
})

const isDark = computed(() => document.documentElement.classList.contains('dark'))

function toggleTheme() {
  const next = isDark.value ? 'light' : 'dark'
  document.documentElement.classList.toggle('dark', next === 'dark')
  localStorage.setItem('mc-theme', next)
}

async function dismissAnnouncement(topicId: string) {
  dismissedLocal.value = [ ...dismissedLocal.value, topicId ]
  localStorage.setItem('mc-dismissed-announcements', JSON.stringify(dismissedLocal.value))
  if (auth.value.user) {
    const token = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content || ''
    await fetch(`${routes.app}/forum/announcements/dismiss`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': token },
      credentials: 'same-origin',
      body: JSON.stringify({ topic_id: topicId }),
    })
  }
}
</script>

<template>
  <div class="min-h-dvh bg-background" :style="tokenStyle">
    <TemplateAssets />
    <header class="sticky top-0 z-40 border-b bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/80">
      <div v-if="portalHeaderExtraSlot" v-html="portalHeaderExtraSlot" />
      <div class="mx-auto flex h-14 max-w-6xl items-center justify-between px-4">
        <Link :href="routes.home" class="flex items-center gap-2 text-sm font-semibold tracking-tight no-underline text-foreground">
          <img v-if="activeTemplate?.logoUrl" :src="activeTemplate.logoUrl" alt="Logo" class="h-7 w-auto">
          <span>Mcweb</span>
        </Link>

        <div class="flex items-center gap-1 sm:gap-2">
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
          <Button v-if="auth.user && messagesUnread" as-child variant="ghost" size="icon" class="relative">
            <Link :href="messagesUnread.url" aria-label="私信">
              <Mail class="h-4 w-4" />
              <Badge
                v-if="messagesUnread.count > 0"
                variant="danger"
                class="absolute -right-1 -top-1 h-4 min-w-4 px-1 text-[10px]"
              >
                {{ messagesUnread.count > 99 ? '99+' : messagesUnread.count }}
              </Badge>
            </Link>
          </Button>
          <Button v-if="cart" as-child variant="ghost" size="icon" class="relative">
            <Link :href="cart.url" aria-label="购物车">
              <ShoppingCart class="h-4 w-4" />
              <Badge
                v-if="cart.count > 0"
                variant="danger"
                class="absolute -right-1 -top-1 h-4 min-w-4 px-1 text-[10px]"
              >
                {{ cart.count > 99 ? '99+' : cart.count }}
              </Badge>
            </Link>
          </Button>
          <div class="mx-1 hidden h-6 w-px bg-border sm:block" />
          <Link
            v-if="auth.user"
            :href="routes.forumUser(auth.user.username)"
            class="max-w-[8rem] truncate text-sm text-muted-foreground hover:text-foreground sm:max-w-none"
          >
            {{ auth.user.username }}
          </Link>
          <Button v-else as-child variant="outline" size="sm">
            <Link :href="routes.signIn">登录</Link>
          </Button>
        </div>
      </div>

      <PortalSubnav
        :logged-in="!!auth.user"
        :forum-unread="forumUnread"
        :forum-assigned="forumAssigned"
        :messages-unread="messagesUnread"
        :cart="cart"
      />
    </header>

    <div v-if="visibleAnnouncements.length" class="border-b bg-amber-50 text-amber-950 dark:bg-amber-950 dark:text-amber-100">
      <div class="mx-auto flex max-w-6xl flex-wrap items-center gap-x-4 gap-y-1 px-4 py-2 text-sm">
        <span class="font-medium shrink-0">全站公告</span>
        <Link
          v-for="item in visibleAnnouncements"
          :key="item.id"
          :href="item.url"
          class="truncate hover:underline"
        >
          {{ item.title }}
        </Link>
        <button
          type="button"
          class="ml-auto shrink-0 text-xs underline opacity-80 hover:opacity-100"
          @click="visibleAnnouncements.forEach((item) => dismissAnnouncement(item.id))"
        >
          全部关闭
        </button>
      </div>
    </div>

    <main class="mx-auto max-w-6xl px-4 py-6">
      <FlashMessages />
      <slot />
    </main>
    <ForumShortcuts />
  </div>
</template>
