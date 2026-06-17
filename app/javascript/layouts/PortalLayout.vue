<script setup lang="ts">
import { computed, ref } from 'vue'
import { Link, usePage } from '@inertiajs/vue3'
import { Moon, Sun, Bell, Mail, ShoppingCart, Menu, X } from '@lucide/vue'
import { routes } from '@/lib/routes'
import FlashMessages from '@/components/portal/FlashMessages.vue'
import ForumShortcuts from '@/components/portal/ForumShortcuts.vue'
import PortalSidebar from '@/components/portal/PortalSidebar.vue'
import PortalUserMenu from '@/components/portal/PortalUserMenu.vue'
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

const mobileNavOpen = ref(false)
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

function closeMobileNav() {
  mobileNavOpen.value = false
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

const sidebarProps = computed(() => ({
  loggedIn: !!auth.value.user,
  forumUnread: forumUnread.value,
  forumAssigned: forumAssigned.value,
  messagesUnread: messagesUnread.value,
  cart: cart.value,
}))
</script>

<template>
  <div class="min-h-dvh bg-background" :style="tokenStyle">
    <TemplateAssets />

    <div v-if="portalHeaderExtraSlot" v-html="portalHeaderExtraSlot" />

    <div class="flex min-h-dvh">
      <!-- Desktop sidebar -->
      <div class="hidden lg:fixed lg:inset-y-0 lg:z-40 lg:flex lg:w-64">
        <PortalSidebar v-bind="sidebarProps" />
      </div>

      <!-- Mobile drawer -->
      <Transition
        enter-active-class="transition-opacity duration-200"
        enter-from-class="opacity-0"
        leave-active-class="transition-opacity duration-200"
        leave-to-class="opacity-0"
      >
        <div
          v-if="mobileNavOpen"
          class="fixed inset-0 z-50 bg-black/50 lg:hidden"
          @click="closeMobileNav"
        />
      </Transition>
      <Transition
        enter-active-class="transition-transform duration-200 ease-out"
        enter-from-class="-translate-x-full"
        leave-active-class="transition-transform duration-200 ease-in"
        leave-to-class="-translate-x-full"
      >
        <div v-if="mobileNavOpen" class="fixed inset-y-0 left-0 z-50 lg:hidden">
          <PortalSidebar v-bind="sidebarProps" show-close :on-navigate="closeMobileNav" />
        </div>
      </Transition>

      <!-- Main column -->
      <div class="flex min-w-0 flex-1 flex-col lg:pl-64">
        <header class="sticky top-0 z-30 border-b bg-background/80 backdrop-blur-md supports-[backdrop-filter]:bg-background/60">
          <div class="flex h-14 items-center gap-2 px-4 sm:px-6">
            <Button
              variant="ghost"
              size="icon"
              class="lg:hidden"
              type="button"
              aria-label="打开菜单"
              @click="mobileNavOpen = true"
            >
              <Menu class="h-5 w-5" />
            </Button>

            <div class="flex flex-1 items-center gap-2 min-w-0">
              <Link
                :href="routes.home"
                class="flex items-center gap-2 font-semibold tracking-tight text-foreground no-underline lg:hidden"
              >
                <img v-if="activeTemplate?.logoUrl" :src="activeTemplate.logoUrl" alt="" class="h-7 w-auto">
                <span class="truncate">McWeb</span>
              </Link>
            </div>

            <div class="flex items-center gap-0.5 sm:gap-1">
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
                    class="absolute -right-0.5 -top-0.5 h-4 min-w-4 px-1 text-[10px]"
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
                    class="absolute -right-0.5 -top-0.5 h-4 min-w-4 px-1 text-[10px]"
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
                    class="absolute -right-0.5 -top-0.5 h-4 min-w-4 px-1 text-[10px]"
                  >
                    {{ cart.count > 99 ? '99+' : cart.count }}
                  </Badge>
                </Link>
              </Button>

              <div class="mx-1 hidden h-6 w-px bg-border sm:block" />

              <PortalUserMenu v-if="auth.user" :username="auth.user.username" />
              <Button v-else as-child variant="default" size="sm">
                <Link :href="routes.signIn">登录</Link>
              </Button>
            </div>
          </div>
        </header>

        <div
          v-if="visibleAnnouncements.length"
          class="border-b bg-amber-500/10 text-amber-950 dark:bg-amber-500/10 dark:text-amber-100"
        >
          <div class="flex flex-wrap items-center gap-x-4 gap-y-2 px-4 py-2.5 text-sm sm:px-6">
            <span class="shrink-0 rounded-md bg-amber-500/20 px-2 py-0.5 text-xs font-semibold uppercase tracking-wide">
              公告
            </span>
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
              class="ml-auto shrink-0 rounded-md p-1 hover:bg-amber-500/20"
              aria-label="关闭公告"
              @click="visibleAnnouncements.forEach((item) => dismissAnnouncement(item.id))"
            >
              <X class="h-4 w-4" />
            </button>
          </div>
        </div>

        <main class="flex-1 px-4 py-6 sm:px-6 lg:px-8">
          <FlashMessages />
          <slot />
        </main>
      </div>
    </div>

    <ForumShortcuts />
  </div>
</template>
