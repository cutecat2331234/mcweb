import type { ApplicationShellAdapter } from '@/lib/applicationShell'
import { routes } from '@/lib/routes'

export const storeShell: ApplicationShellAdapter = {
  applicationId: 'store',
  brandKey: 'portal.brand',
  labelKey: 'common.applications.store',
  navigation: [
    {
      id: 'store-browse',
      labelKey: 'common.browse',
      items: [
        { labelKey: 'nav.products', href: routes.store, icon: 'gift' },
        { labelKey: 'nav.compare', href: routes.storeCompare, icon: 'list', requiresAuthentication: true },
        { labelKey: 'nav.recentlyViewed', href: routes.storeRecentlyViewed, icon: 'history', requiresAuthentication: true },
      ],
    },
    {
      id: 'store-personal',
      labelKey: 'common.mine',
      items: [
        { labelKey: 'nav.cart', href: routes.storeCart, icon: 'gift', badgeProp: 'cart.count' },
        { labelKey: 'nav.orders', href: routes.storeOrders, icon: 'archive', requiresAuthentication: true },
        { labelKey: 'nav.wishlist', href: routes.storeWishlist, icon: 'heart', requiresAuthentication: true },
        { labelKey: 'nav.wallet', href: routes.storeWallet, icon: 'wallet', requiresAuthentication: true },
        { labelKey: 'nav.giftCards', href: routes.storeGiftCards, icon: 'gift', requiresAuthentication: true },
        { labelKey: 'nav.shippingAddresses', href: routes.storeShippingAddresses, icon: 'home', visibilityProp: 'storeFeatures.shipping', requiresAuthentication: true },
        { labelKey: 'nav.stockAlerts', href: routes.storeStockAlerts, icon: 'notification', requiresAuthentication: true },
        { labelKey: 'nav.priceAlerts', href: routes.storePriceAlerts, icon: 'notification', requiresAuthentication: true },
        { labelKey: 'nav.availabilityAlerts', href: routes.storeAvailabilityAlerts, icon: 'notification', requiresAuthentication: true },
        { labelKey: 'nav.storePreferences', href: routes.storePreferences, icon: 'settings', requiresAuthentication: true },
      ],
    },
  ],
}
