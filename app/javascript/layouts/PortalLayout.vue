<script setup lang="ts">
import { computed, ref } from 'vue'
import { Link, usePage } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import { Moon, Sun, Bell, Mail, ShoppingCart, Menu, X } from '@lucide/vue'
import { routes } from '@/lib/routes'
import FlashMessages from '@/components/portal/FlashMessages.vue'
import ForumShortcuts from '@/components/portal/ForumShortcuts.vue'
import PortalSidebar from '@/components/portal/PortalSidebar.vue'
import PortalUserMenu from '@/components/portal/PortalUserMenu.vue'
import LanguageSwitcher from '@/components/portal/LanguageSwitcher.vue'
import TemplateAssets from '@/components/portal/TemplateAssets.vue'
import Button from '@/components/ui/Button.vue'
import Badge from '@/components/ui/Badge.vue'
import { useActiveTemplate } from '@/lib/useActiveTemplate'
import { useTheme } from '@/lib/useTheme'
import { readCsrfToken } from '@/lib/csrf'
import { useFeatureFlags } from '@/lib/useFeatureFlags'

const page = usePage()
const { t } = useI18n()
const auth = computed(() => page.props.auth as { user: { username: string } | null })
const notifications = computed(() => page.props.notifications as { unread_count: number; url: string } | undefined)
const forumUnread = computed(() => page.props.forum_unread as { count: number; url: string } | undefined)
const forumNew = computed(() => page.props.forum_new as { count: number; url: string } | undefined)
const forumAssigned = computed(() => page.props.forum_assigned as { count: number; url: string } | undefined)
const forumModerationPending = computed(() => page.props.forum_moderation_pending as { count: number; url: string } | undefined)
const messagesUnread = computed(() => page.props.messages_unread as { count: number; url: string } | undefined)
const cart = computed(() => page.props.cart as { count: number; url: string } | undefined)
const globalAnnouncements = computed(() => page.props.global_announcements as Array<{ title: string; url: string; id: string }> | undefined)
const forumNotices = computed(() => page.props.forum_notices as Array<{ id: number; title: string; message_html: string; style: string; dismissible: boolean; dismiss_url: string }> | undefined)
const dismissedNoticesLocal = ref<number[]>([])
const visibleNotices = computed(() => (forumNotices.value || []).filter((n) => !dismissedNoticesLocal.value.includes(n.id)))

const noticeStyleClasses: Record<string, string> = {
  info: 'border-sky-500/30 bg-sky-500/10 text-sky-950 dark:text-sky-100',
  success: 'border-emerald-500/30 bg-emerald-500/10 text-emerald-950 dark:text-emerald-100',
  warning: 'border-amber-500/30 bg-amber-500/10 text-amber-950 dark:text-amber-100',
  danger: 'border-red-500/30 bg-red-500/10 text-red-950 dark:text-red-100',
}

function noticeClass(style: string): string {
  return noticeStyleClasses[style] || noticeStyleClasses.info
}

async function dismissNotice(notice: { id: number; dismissible: boolean; dismiss_url: string }) {
  dismissedNoticesLocal.value = [ ...dismissedNoticesLocal.value, notice.id ]
  if (auth.value.user && notice.dismissible) {
    const token = readCsrfToken()
    await fetch(notice.dismiss_url, {
      method: 'POST',
      headers: { 'X-CSRF-Token': token },
      credentials: 'same-origin',
    })
  }
}
const { activeTemplate, tokenStyle, portalHeaderExtraSlot, portalFooterSlot } = useActiveTemplate()
const { isDark, toggleTheme } = useTheme()
const { features } = useFeatureFlags()

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

function closeMobileNav() {
  mobileNavOpen.value = false
}

async function dismissAnnouncement(topicId: string) {
  dismissedLocal.value = [ ...dismissedLocal.value, topicId ]
  localStorage.setItem('mc-dismissed-announcements', JSON.stringify(dismissedLocal.value))
  if (auth.value.user) {
    const token = readCsrfToken()
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
  forumNew: forumNew.value,
  forumAssigned: forumAssigned.value,
  forumModerationPending: forumModerationPending.value,
  messagesUnread: messagesUnread.value,
  cart: cart.value,
}))
</script>

<template>
  <div class="min-h-dvh bg-background portal-themed" :style="tokenStyle">
    <TemplateAssets :include-css="false" />

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
        <header
          class="portal-header sticky top-0 z-30 border-b border-sidebar-border bg-sidebar text-sidebar-foreground"
          :style="{ backgroundColor: 'var(--sidebar)', color: 'var(--sidebar-foreground)' }"
        >
          <div class="flex h-14 items-center gap-2 px-4 sm:px-6">
            <Button
              variant="ghost"
              size="icon"
              class="lg:hidden hover:bg-primary/10"
              type="button"
              :aria-label="t('common.openMenu')"
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
                <span class="truncate">{{ t('portal.brand') }}</span>
              </Link>
            </div>

            <div class="flex items-center gap-0.5 sm:gap-1">
              <LanguageSwitcher />

              <Button variant="ghost" size="icon" type="button" :aria-label="t('common.toggleTheme')" @click="toggleTheme">
                <Sun v-if="isDark" class="h-4 w-4" />
                <Moon v-else class="h-4 w-4" />
              </Button>

              <Button v-if="features.forum && auth.user && notifications" as-child variant="ghost" size="icon" class="relative">
                <Link :href="notifications.url" :aria-label="t('common.notifications')">
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

              <Button v-if="features.forum && auth.user && messagesUnread" as-child variant="ghost" size="icon" class="relative">
                <Link :href="messagesUnread.url" :aria-label="t('common.messages')">
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

              <Button v-if="features.store && cart" as-child variant="ghost" size="icon" class="relative">
                <Link :href="cart.url" :aria-label="t('common.cart')">
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
                <Link :href="routes.signIn">{{ t('common.signIn') }}</Link>
              </Button>
            </div>
          </div>
        </header>

        <div
          v-if="features.forum && visibleAnnouncements.length"
          class="border-b bg-amber-500/10 text-amber-950 dark:bg-amber-500/10 dark:text-amber-100"
        >
          <div class="flex flex-wrap items-center gap-x-4 gap-y-2 px-4 py-2.5 text-sm sm:px-6">
            <span class="shrink-0 rounded-md bg-amber-500/20 px-2 py-0.5 text-xs font-semibold uppercase tracking-wide">
              {{ t('common.announcement') }}
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
              :aria-label="t('common.closeAnnouncement')"
              @click="visibleAnnouncements.forEach((item) => dismissAnnouncement(item.id))"
            >
              <X class="h-4 w-4" />
            </button>
          </div>
        </div>

        <div
          v-for="notice in visibleNotices"
          :key="notice.id"
          class="border-b"
          :class="noticeClass(notice.style)"
        >
          <div class="flex flex-wrap items-start gap-x-4 gap-y-1 px-4 py-2.5 text-sm sm:px-6">
            <div class="min-w-0 flex-1">
              <p class="font-semibold">{{ notice.title }}</p>
              <div class="prose prose-sm max-w-none text-current/90" v-html="notice.message_html" />
            </div>
            <button
              v-if="notice.dismissible"
              type="button"
              class="ml-auto shrink-0 rounded-md p-1 hover:bg-black/5 dark:hover:bg-white/10"
              :aria-label="t('common.closeAnnouncement')"
              @click="dismissNotice(notice)"
            >
              <X class="h-4 w-4" />
            </button>
          </div>
        </div>

        <main class="flex-1 px-4 py-6 sm:px-6 lg:px-8">
          <div class="mx-auto w-full max-w-6xl">
            <FlashMessages />
            <Transition name="page-fade" mode="out-in">
              <div :key="page.url" class="min-h-[1px]">
                <slot />
              </div>
            </Transition>
          </div>
        </main>
      </div>
    </div>

    <ForumShortcuts v-if="features.forum" />

    <footer v-if="portalFooterSlot" class="portal-footer border-t border-border bg-background px-4 py-6 sm:px-6" v-html="portalFooterSlot" />
  </div>
</template>
