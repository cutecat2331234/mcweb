<script setup lang="ts">
import { computed } from 'vue'
import { Link, usePage } from '@inertiajs/vue3'
import { routes } from '@/lib/routes'
import Badge from '@/components/ui/Badge.vue'

interface NavItem {
  label: string
  href: string
  badge?: number
  loginRequired?: boolean
}

interface NavGroup {
  key: string
  label: string
  items: NavItem[]
}

const props = defineProps<{
  loggedIn: boolean
  forumUnread?: { count: number; url: string }
  forumAssigned?: { count: number; url: string }
  messagesUnread?: { count: number; url: string }
  cart?: { count: number; url: string }
}>()

const page = usePage()

const currentPath = computed(() => page.url.split('?')[0])

function isActive(href: string) {
  const path = currentPath.value
  if (href === routes.home) return path === '/'
  if (href === routes.forum) return path.startsWith('/forum')
  if (href === routes.store) return path.startsWith('/store')
  return path === href || path.startsWith(`${href}/`)
}

function linkClass(href: string) {
  return isActive(href)
    ? 'text-foreground font-medium'
    : 'text-muted-foreground hover:text-foreground'
}

const activeSection = computed<'forum' | 'store'>(() =>
  currentPath.value.startsWith('/store') ? 'store' : 'forum',
)

const forumBrowseItems: NavItem[] = [
  { label: '板块', href: routes.forum },
  { label: '最新', href: routes.forumLatest },
  { label: '动态', href: routes.forumActivity },
  { label: '搜索', href: routes.forumSearch },
  { label: '标签', href: routes.forumTags },
  { label: '徽章', href: routes.forumBadges },
  { label: '成员', href: routes.forumMembers },
]

const forumPersonalItems = computed<NavItem[]>(() => {
  if (!props.loggedIn) return []
  return [
    { label: '关注主题', href: routes.forumWatching, loginRequired: true },
    { label: '关注标签', href: routes.forumWatchedTags, loginRequired: true },
    { label: '标签主题', href: routes.forumWatchedTagTopics, loginRequired: true },
    { label: '关注用户', href: routes.forumFollowing, loginRequired: true },
    { label: '书签', href: routes.forumBookmarks, loginRequired: true },
    {
      label: '未读',
      href: props.forumUnread?.url || routes.forumUnread,
      badge: props.forumUnread?.count,
      loginRequired: true,
    },
    ...(props.forumAssigned ? [ {
      label: '指派',
      href: props.forumAssigned.url,
      badge: props.forumAssigned.count,
      loginRequired: true,
    } ] : []),
    {
      label: '私信',
      href: props.messagesUnread?.url || routes.forumMessages,
      badge: props.messagesUnread?.count,
      loginRequired: true,
    },
    { label: '草稿', href: routes.forumDrafts, loginRequired: true },
    { label: '偏好', href: routes.forumPreferences, loginRequired: true },
    { label: '拉黑', href: routes.forumBlocks, loginRequired: true },
    { label: '忽略', href: routes.forumIgnores, loginRequired: true },
    { label: '静音', href: routes.forumMuted, loginRequired: true },
  ]
})

const storeBrowseItems: NavItem[] = [
  { label: '商品', href: routes.store },
  { label: '对比', href: routes.storeCompare, loginRequired: true },
  { label: '最近浏览', href: routes.storeRecentlyViewed, loginRequired: true },
]

const storePersonalItems = computed<NavItem[]>(() => {
  if (!props.loggedIn) return []
  const items: NavItem[] = [
    { label: '我的订单', href: routes.storeOrders, loginRequired: true },
    { label: '心愿单', href: routes.storeWishlist, loginRequired: true },
    { label: '收货地址', href: routes.storeShippingAddresses, loginRequired: true },
    { label: '商店余额', href: routes.storeWallet, loginRequired: true },
    { label: '礼品卡', href: routes.storeGiftCards, loginRequired: true },
    { label: '到货通知', href: routes.storeStockAlerts, loginRequired: true },
    { label: '降价提醒', href: routes.storePriceAlerts, loginRequired: true },
    { label: '上架通知', href: routes.storeAvailabilityAlerts, loginRequired: true },
    { label: '商城通知', href: routes.storePreferences, loginRequired: true },
  ]
  if (props.cart) {
    items.splice(2, 0, {
      label: '购物车',
      href: props.cart.url,
      badge: props.cart.count > 0 ? props.cart.count : undefined,
      loginRequired: true,
    })
  }
  return items
})

const visibleGroups = computed<NavGroup[]>(() => {
  if (activeSection.value === 'store') {
    const groups: NavGroup[] = [
      { key: 'store-browse', label: '商城', items: storeBrowseItems.filter((item) => !item.loginRequired || props.loggedIn) },
    ]
    if (props.loggedIn) {
      groups.push({ key: 'store-mine', label: '我的商城', items: storePersonalItems.value })
    }
    return groups
  }

  const groups: NavGroup[] = [
    { key: 'forum-browse', label: '论坛', items: forumBrowseItems },
  ]
  if (props.loggedIn) {
    groups.push({ key: 'forum-mine', label: '我的论坛', items: forumPersonalItems.value })
  }
  return groups
})
</script>

<template>
  <nav class="border-t bg-muted/30">
    <div class="mx-auto max-w-6xl px-4">
      <div class="flex h-10 items-center gap-1 overflow-x-auto text-sm [-ms-overflow-style:none] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
        <div class="flex shrink-0 items-center gap-1 pr-2">
          <Link
            :href="routes.forum"
            class="rounded-md px-2.5 py-1 transition-colors"
            :class="activeSection === 'forum' ? 'bg-background text-foreground font-medium shadow-sm' : 'text-muted-foreground hover:text-foreground'"
          >
            论坛
          </Link>
          <Link
            :href="routes.store"
            class="rounded-md px-2.5 py-1 transition-colors"
            :class="activeSection === 'store' ? 'bg-background text-foreground font-medium shadow-sm' : 'text-muted-foreground hover:text-foreground'"
          >
            商城
          </Link>
        </div>

        <div class="mx-1 h-5 w-px shrink-0 bg-border" />

        <template v-for="(group, groupIndex) in visibleGroups" :key="group.key">
          <div v-if="groupIndex > 0" class="mx-1 h-5 w-px shrink-0 bg-border" />
          <div class="flex shrink-0 items-center gap-2">
            <span class="shrink-0 text-xs font-medium text-muted-foreground">{{ group.label }}</span>
            <div class="flex items-center gap-3">
              <Link
                v-for="item in group.items"
                :key="item.href"
                :href="item.href"
                class="inline-flex shrink-0 items-center gap-1 whitespace-nowrap transition-colors"
                :class="linkClass(item.href)"
              >
                {{ item.label }}
                <Badge
                  v-if="item.badge && item.badge > 0"
                  variant="danger"
                  class="h-4 min-w-4 px-1 text-[10px]"
                >
                  {{ item.badge > 99 ? '99+' : item.badge }}
                </Badge>
              </Link>
            </div>
          </div>
        </template>
      </div>
    </div>
  </nav>
</template>
