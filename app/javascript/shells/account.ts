import type { ApplicationShellAdapter } from '@/lib/applicationShell'
import { routes } from '@/lib/routes'

export const accountShell: ApplicationShellAdapter = {
  applicationId: 'account',
  brandKey: 'portal.brand',
  navigation: [
    {
      id: 'account',
      labelKey: 'accountCenter.title',
      items: [
        { labelKey: 'accountCenter.actions.profile', href: routes.account },
        { labelKey: 'common.notifications', href: routes.accountNotifications },
        { labelKey: 'accountCenter.actions.security', href: routes.security },
        { labelKey: 'accountCenter.security.sessions', href: routes.sessionsManagement },
        { labelKey: 'accountCenter.actions.minecraft', href: routes.minecraftLink },
      ],
    },
  ],
}
