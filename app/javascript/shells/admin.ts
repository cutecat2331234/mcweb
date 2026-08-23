import type { ApplicationShellAdapter } from '@/lib/applicationShell'

export const adminShell: ApplicationShellAdapter = {
  applicationId: 'admin',
  brandKey: 'admin.title',
  navigation: [
    {
      id: 'admin-overview',
      labelKey: 'admin.overview',
      items: [
        { labelKey: 'admin.dashboard.title', href: '/admin' },
        { labelKey: 'admin.users', href: '/admin/users' },
        { labelKey: 'admin.system', href: '/admin/system/settings' },
      ],
    },
  ],
}
