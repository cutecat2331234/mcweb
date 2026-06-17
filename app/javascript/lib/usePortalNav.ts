import { computed, type ComputedRef } from 'vue'
import { usePage } from '@inertiajs/vue3'
import { routes, appPrefix } from '@/lib/routes'

export interface PortalNavItem {
  label: string
  href: string
  badge?: number
  loginRequired?: boolean
  icon?: string
}

export interface PortalNavGroup {
  key: string
  label: string
  items: PortalNavItem[]
}

export interface PortalNavOptions {
  loggedIn: boolean
  forumUnread?: { count: number; url: string }
  forumAssigned?: { count: number; url: string }
  messagesUnread?: { count: number; url: string }
  cart?: { count: number; url: string }
}

export function usePortalNav(options: PortalNavOptions | ComputedRef<PortalNavOptions>) {
  const page = usePage()
  const opts = computed(() => ('value' in options ? options.value : options))

  const currentPath = computed(() => page.url.split('?')[0])

  const activeSection = computed<'forum' | 'store'>(() =>
    currentPath.value.startsWith(`${appPrefix}/store`) ? 'store' : 'forum',
  )

  function isActive(href: string) {
    const path = currentPath.value
    if (href === routes.forum) {
      return path === routes.forum || path.startsWith(`${routes.forum}/`)
    }
    if (href === routes.store) {
      return path === routes.store || (path.startsWith(`${appPrefix}/store/products`) && !path.includes('/recently_viewed'))
    }
    return path === href || path.startsWith(`${href}/`)
  }

  function isSectionActive(section: 'forum' | 'store') {
    return activeSection.value === section
  }

  const forumBrowseItems: PortalNavItem[] = [
    { label: '板块', href: routes.forum, icon: 'layout-grid' },
    { label: '最新', href: routes.forumLatest, icon: 'sparkles' },
    { label: '动态', href: routes.forumActivity, icon: 'activity' },
    { label: '搜索', href: routes.forumSearch, icon: 'search' },
    { label: '标签', href: routes.forumTags, icon: 'tag' },
    { label: '徽章', href: routes.forumBadges, icon: 'award' },
    { label: '成员', href: routes.forumMembers, icon: 'users' },
  ]

  const forumPersonalItems = computed<PortalNavItem[]>(() => {
    if (!opts.value.loggedIn) return []
    return [
      { label: '关注主题', href: routes.forumWatching, loginRequired: true, icon: 'eye' },
      { label: '关注标签', href: routes.forumWatchedTags, loginRequired: true, icon: 'bookmark' },
      { label: '标签主题', href: routes.forumWatchedTagTopics, loginRequired: true, icon: 'list' },
      { label: '关注用户', href: routes.forumFollowing, loginRequired: true, icon: 'user-plus' },
      { label: '书签', href: routes.forumBookmarks, loginRequired: true, icon: 'bookmark' },
      {
        label: '未读',
        href: opts.value.forumUnread?.url || routes.forumUnread,
        badge: opts.value.forumUnread?.count,
        loginRequired: true,
        icon: 'inbox',
      },
      ...(opts.value.forumAssigned ? [ {
        label: '指派',
        href: opts.value.forumAssigned.url,
        badge: opts.value.forumAssigned.count,
        loginRequired: true,
        icon: 'list',
      } ] : []),
      {
        label: '私信',
        href: opts.value.messagesUnread?.url || routes.forumMessages,
        badge: opts.value.messagesUnread?.count,
        loginRequired: true,
        icon: 'mail',
      },
      { label: '草稿', href: routes.forumDrafts, loginRequired: true, icon: 'file-text' },
      { label: '偏好', href: routes.forumPreferences, loginRequired: true, icon: 'settings' },
      { label: '拉黑', href: routes.forumBlocks, loginRequired: true, icon: 'ban' },
      { label: '忽略', href: routes.forumIgnores, loginRequired: true, icon: 'user-minus' },
      { label: '静音', href: routes.forumMuted, loginRequired: true, icon: 'volume-off' },
    ]
  })

  const storeBrowseItems: PortalNavItem[] = [
    { label: '商品', href: routes.store, icon: 'shopping-bag' },
    { label: '对比', href: routes.storeCompare, loginRequired: true, icon: 'sliders' },
    { label: '最近浏览', href: routes.storeRecentlyViewed, loginRequired: true, icon: 'history' },
  ]

  const storePersonalItems = computed<PortalNavItem[]>(() => {
    if (!opts.value.loggedIn) return []
    const items: PortalNavItem[] = [
      { label: '我的订单', href: routes.storeOrders, loginRequired: true, icon: 'package' },
      { label: '心愿单', href: routes.storeWishlist, loginRequired: true, icon: 'heart' },
      { label: '收货地址', href: routes.storeShippingAddresses, loginRequired: true, icon: 'map-pin' },
      { label: '商店余额', href: routes.storeWallet, loginRequired: true, icon: 'wallet' },
      { label: '礼品卡', href: routes.storeGiftCards, loginRequired: true, icon: 'gift' },
      { label: '到货通知', href: routes.storeStockAlerts, loginRequired: true, icon: 'bell' },
      { label: '降价提醒', href: routes.storePriceAlerts, loginRequired: true, icon: 'arrow-down' },
      { label: '上架通知', href: routes.storeAvailabilityAlerts, loginRequired: true, icon: 'bell' },
      { label: '商城通知', href: routes.storePreferences, loginRequired: true, icon: 'settings' },
    ]
    if (opts.value.cart) {
      items.splice(1, 0, {
        label: '购物车',
        href: opts.value.cart.url,
        badge: opts.value.cart.count > 0 ? opts.value.cart.count : undefined,
        loginRequired: true,
        icon: 'shopping-cart',
      })
    }
    return items
  })

  const navGroups = computed<PortalNavGroup[]>(() => {
    if (activeSection.value === 'store') {
      const groups: PortalNavGroup[] = [
        {
          key: 'store-browse',
          label: '浏览',
          items: storeBrowseItems.filter((item) => !item.loginRequired || opts.value.loggedIn),
        },
      ]
      if (opts.value.loggedIn) {
        groups.push({ key: 'store-mine', label: '我的', items: storePersonalItems.value })
      }
      return groups
    }

    const groups: PortalNavGroup[] = [
      { key: 'forum-browse', label: '浏览', items: forumBrowseItems },
    ]
    if (opts.value.loggedIn) {
      groups.push({ key: 'forum-mine', label: '我的', items: forumPersonalItems.value })
    }
    return groups
  })

  return {
    currentPath,
    activeSection,
    navGroups,
    isActive,
    isSectionActive,
  }
}
