import type { ApplicationShellAdapter } from '@/lib/applicationShell'
import { routes } from '@/lib/routes'

export const staffShell: ApplicationShellAdapter = {
  applicationId: 'staff',
  brandKey: 'staffWorkspace.brand',
  navigation: [
    {
      id: 'staff-workspace',
      labelKey: 'nav.staffWorkspace',
      items: [
        { labelKey: 'staffWorkspace.navigation.overview', href: routes.staff },
        { labelKey: 'staffWorkspace.navigation.queue', href: routes.staffModerationCases },
        { labelKey: 'staffWorkspace.forumApprovals.title', href: routes.staffForumApprovals },
        { labelKey: 'staffWorkspace.navigation.reportAppeals', href: routes.staffReportAppeals },
      ],
    },
  ],
}
