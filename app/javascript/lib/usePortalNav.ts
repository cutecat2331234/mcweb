import { computed, type ComputedRef } from 'vue'
import { useI18n } from 'vue-i18n'
import { usePage } from '@inertiajs/vue3'
import { routes, appPrefix } from '@/lib/routes'
import { resolveFeatureFlags } from '@/lib/featureFlags'
import { resolveStoreFeatures } from '@/lib/storeFeatures'

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
  defaultExpanded?: boolean
}

export interface PortalNavOptions {
  loggedIn: boolean
  forumUnread?: { count: number; url: string }
  forumNew?: { count: number; url: string }
  forumAssigned?: { count: number; url: string }
  forumModerationPending?: { count: number; url: string }
  messagesUnread?: { count: number; url: string }
  cart?: { count: number; url: string }
}

function pathMatches(path: string, href: string) {
  return path === href || path.startsWith(`${href}/`)
}

export function usePortalNav(options: PortalNavOptions | ComputedRef<PortalNavOptions>) {
  const page = usePage()
  const { t } = useI18n()
  const opts = computed(() => ('value' in options ? options.value : options))

  const currentPath = computed(() => page.url.split('?')[0])

  const features = computed(() =>
    resolveFeatureFlags(page.props.features as Parameters<typeof resolveFeatureFlags>[0]),
  )

  const storeFeatures = computed(() =>
    resolveStoreFeatures(page.props.storeFeatures as Parameters<typeof resolveStoreFeatures>[0]),
  )

  const activeSection = computed<'forum' | 'store'>(() => {
    const onStorePath = currentPath.value.startsWith(`${appPrefix}/store`)
    if (onStorePath && features.value.store) return 'store'
    if (features.value.forum) return 'forum'
    if (features.value.store) return 'store'
    return 'forum'
  })

  const forumBrowseItems = computed<PortalNavItem[]>(() => [
    { label: t('nav.sections'), href: routes.forum, icon: 'layout-grid' },
    { label: t('nav.latest'), href: routes.forumLatest, icon: 'sparkles' },
    { label: t('nav.top'), href: routes.forumTop, icon: 'flame' },
    { label: t('nav.activity'), href: routes.forumActivity, icon: 'activity' },
    { label: t('nav.search'), href: routes.forumSearch, icon: 'search' },
    { label: t('nav.tags'), href: routes.forumTags, icon: 'tag' },
    { label: t('nav.badges'), href: routes.forumBadges, icon: 'award' },
    { label: t('nav.members'), href: routes.forumMembers, icon: 'users' },
    { label: t('nav.staff'), href: routes.forumStaff, icon: 'shield' },
    { label: t('nav.statistics'), href: routes.forumStatistics, icon: 'activity' },
    { label: t('nav.help'), href: routes.forumHelp, icon: 'file-text' },
    ...((page.props.forum_nav_pages as Array<{ label: string; slug: string }> | undefined) || []).map((p) => ({
      label: p.label,
      href: routes.forumPage(p.slug),
      icon: 'file-text',
    })),
  ])

  const forumPersonalItems = computed<PortalNavItem[]>(() => {
    if (!opts.value.loggedIn) return []
    return [
      {
        label: t('nav.new'),
        href: opts.value.forumNew?.url || routes.forumNew,
        badge: opts.value.forumNew?.count,
        loginRequired: true,
        icon: 'circle-dot',
      },
      { label: t('nav.watching'), href: routes.forumWatching, loginRequired: true, icon: 'eye' },
      { label: t('nav.watchedTags'), href: routes.forumWatchedTags, loginRequired: true, icon: 'bookmark' },
      { label: t('nav.watchedTagTopics'), href: routes.forumWatchedTagTopics, loginRequired: true, icon: 'list' },
      { label: t('nav.following'), href: routes.forumFollowing, loginRequired: true, icon: 'user-plus' },
      { label: t('nav.bookmarks'), href: routes.forumBookmarks, loginRequired: true, icon: 'bookmark' },
      {
        label: t('nav.unread'),
        href: opts.value.forumUnread?.url || routes.forumUnread,
        badge: opts.value.forumUnread?.count,
        loginRequired: true,
        icon: 'inbox',
      },
      ...(opts.value.forumAssigned ? [ {
        label: t('nav.assigned'),
        href: opts.value.forumAssigned.url,
        badge: opts.value.forumAssigned.count,
        loginRequired: true,
        icon: 'list',
      } ] : []),
      ...(opts.value.forumModerationPending ? [ {
        label: t('nav.moderationApprovals'),
        href: opts.value.forumModerationPending.url,
        badge: opts.value.forumModerationPending.count,
        loginRequired: true,
        icon: 'shield',
      } ] : []),
      {
        label: t('nav.messages'),
        href: opts.value.messagesUnread?.url || routes.forumMessages,
        badge: opts.value.messagesUnread?.count,
        loginRequired: true,
        icon: 'mail',
      },
      { label: t('nav.drafts'), href: routes.forumDrafts, loginRequired: true, icon: 'file-text' },
      { label: t('nav.preferences'), href: routes.forumPreferences, loginRequired: true, icon: 'settings' },
      { label: t('nav.blocks'), href: routes.forumBlocks, loginRequired: true, icon: 'ban' },
      { label: t('nav.ignores'), href: routes.forumIgnores, loginRequired: true, icon: 'user-minus' },
      { label: t('nav.muted'), href: routes.forumMuted, loginRequired: true, icon: 'volume-off' },
    ]
  })

  const storeBrowseItems = computed<PortalNavItem[]>(() => [
    { label: t('nav.products'), href: routes.store, icon: 'shopping-bag' },
    { label: t('nav.compare'), href: routes.storeCompare, loginRequired: true, icon: 'sliders' },
    { label: t('nav.recentlyViewed'), href: routes.storeRecentlyViewed, loginRequired: true, icon: 'history' },
  ])

  const storePersonalItems = computed<PortalNavItem[]>(() => {
    if (!opts.value.loggedIn) return []
    return [
      { label: t('nav.orders'), href: routes.storeOrders, loginRequired: true, icon: 'package' },
      ...(opts.value.cart ? [ {
        label: t('nav.cart'),
        href: opts.value.cart.url,
        badge: opts.value.cart.count > 0 ? opts.value.cart.count : undefined,
        loginRequired: true,
        icon: 'shopping-cart',
      } ] : []),
      { label: t('nav.wishlist'), href: routes.storeWishlist, loginRequired: true, icon: 'heart' },
      ...(storeFeatures.value.shipping ? [ {
        label: t('nav.shippingAddresses'),
        href: routes.storeShippingAddresses,
        loginRequired: true,
        icon: 'map-pin',
      } ] : []),
      { label: t('nav.wallet'), href: routes.storeWallet, loginRequired: true, icon: 'wallet' },
      { label: t('nav.giftCards'), href: routes.storeGiftCards, loginRequired: true, icon: 'gift' },
      { label: t('nav.stockAlerts'), href: routes.storeStockAlerts, loginRequired: true, icon: 'bell' },
      { label: t('nav.priceAlerts'), href: routes.storePriceAlerts, loginRequired: true, icon: 'arrow-down' },
      { label: t('nav.availabilityAlerts'), href: routes.storeAvailabilityAlerts, loginRequired: true, icon: 'bell' },
      { label: t('nav.storePreferences'), href: routes.storePreferences, loginRequired: true, icon: 'settings' },
    ]
  })

  const navGroups = computed<PortalNavGroup[]>(() => {
    if (activeSection.value === 'store' && features.value.store) {
      const groups: PortalNavGroup[] = [
        {
          key: 'store-browse',
          label: t('common.browse'),
          defaultExpanded: true,
          items: storeBrowseItems.value.filter((item) => !item.loginRequired || opts.value.loggedIn),
        },
      ]
      if (opts.value.loggedIn) {
        groups.push({ key: 'store-mine', label: t('common.mine'), defaultExpanded: false, items: storePersonalItems.value })
      }
      return groups
    }

    if (!features.value.forum) return []

    const groups: PortalNavGroup[] = [
      { key: 'forum-browse', label: t('common.browse'), defaultExpanded: true, items: forumBrowseItems.value },
    ]
    if (opts.value.loggedIn) {
      groups.push({ key: 'forum-mine', label: t('common.mine'), defaultExpanded: false, items: forumPersonalItems.value })
    }
    return groups
  })

  const allNavHrefs = computed(() => navGroups.value.flatMap((group) => group.items.map((item) => item.href)))

  function isActive(href: string) {
    const path = currentPath.value

    if (href === routes.forum) {
      const matches = path === routes.forum || path.startsWith(`${routes.forum}/`)
      if (!matches) return false
      const better = allNavHrefs.value
        .filter((h) => h !== href && h.startsWith(`${routes.forum}/`) && pathMatches(path, h))
        .sort((a, b) => b.length - a.length)[0]
      return !better
    }

    if (href === routes.store) {
      return path === routes.store || (path.startsWith(`${appPrefix}/store/products`) && !path.includes('/recently_viewed'))
    }

    if (!pathMatches(path, href)) return false

    const moreSpecific = allNavHrefs.value
      .filter((other) => other !== href && other.startsWith(`${href}/`) && pathMatches(path, other))
      .sort((a, b) => b.length - a.length)[0]

    return !moreSpecific
  }

  function isSectionActive(section: 'forum' | 'store') {
    return activeSection.value === section
  }

  return {
    currentPath,
    activeSection,
    navGroups,
    isActive,
    isSectionActive,
  }
}
