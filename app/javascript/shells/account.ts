import type { ApplicationShellAdapter } from '@/lib/applicationShell'
import { routes } from '@/lib/routes'

export const accountShell: ApplicationShellAdapter = {
  applicationId: 'account',
  brandKey: 'portal.brand',
  labelKey: 'accountCenter.title',
  navigation: [
    {
      id: 'account',
      labelKey: 'accountCenter.title',
      items: [
        { labelKey: 'accountCenter.overview', href: routes.account, icon: 'user' },
        {
          labelKey: 'common.notifications',
          href: routes.accountNotifications,
          badgeProp: 'notifications.unread_count',
          icon: 'notification',
        },
        { labelKey: 'accountCenter.actions.profile', href: routes.identityProfile, icon: 'user' },
        { labelKey: 'accountCenter.actions.security', href: routes.security, icon: 'lock' },
        { labelKey: 'accountCenter.security.sessions', href: routes.sessionsManagement, icon: 'users' },
        { labelKey: 'accountCenter.actions.minecraft', href: routes.minecraftLink, icon: 'apps', visibilityProp: 'features.minecraft' },
      ],
    },
  ],
}
