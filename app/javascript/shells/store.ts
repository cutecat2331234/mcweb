import type { ApplicationShellAdapter } from '@/lib/applicationShell'
import { routes } from '@/lib/routes'

export const storeShell: ApplicationShellAdapter = {
  applicationId: 'store',
  brandKey: 'portal.brand',
  navigation: [
    {
      id: 'store-browse',
      labelKey: 'common.browse',
      items: [
        { labelKey: 'nav.products', href: routes.store },
        { labelKey: 'nav.compare', href: routes.storeCompare },
        { labelKey: 'nav.recentlyViewed', href: routes.storeRecentlyViewed },
      ],
    },
    {
      id: 'store-personal',
      labelKey: 'common.mine',
      items: [
        { labelKey: 'nav.cart', href: routes.storeCart, badgeProp: 'cart.count' },
        { labelKey: 'nav.orders', href: routes.storeOrders, requiresAuthentication: true },
        { labelKey: 'nav.wishlist', href: routes.storeWishlist, requiresAuthentication: true },
        { labelKey: 'nav.wallet', href: routes.storeWallet, requiresAuthentication: true },
        { labelKey: 'nav.storePreferences', href: routes.storePreferences, requiresAuthentication: true },
      ],
    },
  ],
}
