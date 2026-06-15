<script setup lang="ts">
import { computed, ref } from 'vue'
import { Link, usePage } from '@inertiajs/vue3'
import { Moon, Sun, Bell } from '@lucide/vue'
import { routes } from '@/lib/routes'
import FlashMessages from '@/components/portal/FlashMessages.vue'
import ForumShortcuts from '@/components/portal/ForumShortcuts.vue'
import Button from '@/components/ui/Button.vue'
import Badge from '@/components/ui/Badge.vue'

const page = usePage()
const auth = computed(() => page.props.auth as { user: { username: string } | null })
const notifications = computed(() => page.props.notifications as { unread_count: number; url: string } | undefined)
const forumUnread = computed(() => page.props.forum_unread as { count: number; url: string } | undefined)
const forumAssigned = computed(() => page.props.forum_assigned as { count: number; url: string } | undefined)
const messagesUnread = computed(() => page.props.messages_unread as { count: number; url: string } | undefined)
const cart = computed(() => page.props.cart as { count: number; url: string } | undefined)
const globalAnnouncements = computed(() => page.props.global_announcements as Array<{ title: string; url: string; id: string }> | undefined)

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
    await fetch('/forum/announcements/dismiss', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': token },
      credentials: 'same-origin',
      body: JSON.stringify({ topic_id: topicId }),
    })
  }
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
            <Link :href="routes.forumActivity" class="hover:text-foreground transition-colors">动态</Link>
            <Link :href="routes.forumSearch" class="hover:text-foreground transition-colors">搜索</Link>
            <Link :href="routes.forumTags" class="hover:text-foreground transition-colors">标签</Link>
            <Link :href="routes.forumBadges" class="hover:text-foreground transition-colors">徽章</Link>
            <Link v-if="auth.user" :href="routes.forumWatching" class="hover:text-foreground transition-colors">关注主题</Link>
            <Link v-if="auth.user" :href="routes.forumWatchedTags" class="hover:text-foreground transition-colors">关注标签</Link>
            <Link v-if="auth.user" :href="routes.forumWatchedTagTopics" class="hover:text-foreground transition-colors">标签主题</Link>
            <Link v-if="auth.user" :href="routes.forumFollowing" class="hover:text-foreground transition-colors">关注用户</Link>
            <Link v-if="auth.user" :href="routes.forumBookmarks" class="hover:text-foreground transition-colors">书签</Link>
            <Link v-if="auth.user" :href="routes.forumBlocks" class="hover:text-foreground transition-colors">拉黑</Link>
            <Link v-if="auth.user" :href="routes.forumIgnores" class="hover:text-foreground transition-colors">忽略</Link>
            <Link v-if="auth.user" :href="routes.forumMuted" class="hover:text-foreground transition-colors">静音</Link>
            <Link :href="routes.forumMembers" class="hover:text-foreground transition-colors">成员</Link>
            <Link v-if="auth.user" :href="routes.forumUnread" class="hover:text-foreground transition-colors">未读</Link>
            <Link v-if="auth.user && forumAssigned" :href="forumAssigned.url" class="hover:text-foreground transition-colors">指派</Link>
            <Link v-if="auth.user" :href="routes.forumMessages" class="hover:text-foreground transition-colors">私信</Link>
            <Link v-if="auth.user" :href="routes.forumPreferences" class="hover:text-foreground transition-colors">偏好</Link>
            <Link v-if="auth.user" :href="routes.forumDrafts" class="hover:text-foreground transition-colors">草稿</Link>
            <Link :href="routes.store" class="hover:text-foreground transition-colors">商城</Link>
            <Link v-if="auth.user" :href="routes.storeWishlist" class="hover:text-foreground transition-colors">心愿单</Link>
            <Link v-if="auth.user" :href="routes.storeRecentlyViewed" class="hover:text-foreground transition-colors">最近浏览</Link>
            <Link v-if="auth.user" :href="routes.storeCompare" class="hover:text-foreground transition-colors">对比</Link>
            <Link v-if="auth.user" :href="routes.storeStockAlerts" class="hover:text-foreground transition-colors">到货通知</Link>
            <Link v-if="auth.user" :href="routes.storePriceAlerts" class="hover:text-foreground transition-colors">降价提醒</Link>
            <Link v-if="auth.user" :href="routes.storeAvailabilityAlerts" class="hover:text-foreground transition-colors">上架通知</Link>
            <Link v-if="auth.user" :href="routes.storeShippingAddresses" class="hover:text-foreground transition-colors">收货地址</Link>
            <Link v-if="auth.user" :href="routes.storeWallet" class="hover:text-foreground transition-colors">商店余额</Link>
            <Link v-if="auth.user" :href="routes.storePreferences" class="hover:text-foreground transition-colors">商城通知</Link>
            <Link v-if="auth.user" :href="routes.storeOrders" class="hover:text-foreground transition-colors">我的订单</Link>
            <Link v-if="auth.user" :href="routes.storeGiftCards" class="hover:text-foreground transition-colors">礼品卡</Link>
            <Link v-if="cart" :href="cart.url" class="hover:text-foreground transition-colors">
              购物车<span v-if="cart.count > 0" class="ml-1 text-primary">({{ cart.count }})</span>
            </Link>
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
          <Button v-if="auth.user && messagesUnread" as-child variant="ghost" size="sm" class="relative hidden md:inline-flex">
            <Link :href="messagesUnread.url">
              私信
              <Badge
                v-if="messagesUnread.count > 0"
                variant="danger"
                class="ml-1 h-4 min-w-4 px-1 text-[10px]"
              >
                {{ messagesUnread.count > 99 ? '99+' : messagesUnread.count }}
              </Badge>
            </Link>
          </Button>
          <Button v-if="auth.user && forumUnread" as-child variant="ghost" size="sm" class="relative hidden md:inline-flex">
            <Link :href="forumUnread.url">
              未读
              <Badge
                v-if="forumUnread.count > 0"
                variant="danger"
                class="ml-1 h-4 min-w-4 px-1 text-[10px]"
              >
                {{ forumUnread.count > 99 ? '99+' : forumUnread.count }}
              </Badge>
            </Link>
          </Button>
          <Button v-if="auth.user && forumAssigned" as-child variant="ghost" size="sm" class="relative hidden md:inline-flex">
            <Link :href="forumAssigned.url">
              指派
              <Badge
                v-if="forumAssigned.count > 0"
                variant="danger"
                class="ml-1 h-4 min-w-4 px-1 text-[10px]"
              >
                {{ forumAssigned.count > 99 ? '99+' : forumAssigned.count }}
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
