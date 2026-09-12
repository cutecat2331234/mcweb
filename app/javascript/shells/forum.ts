import { defineAsyncComponent } from 'vue'

import type { ApplicationShellAdapter } from '@/lib/applicationShell'
import { routes } from '@/lib/routes'

export const forumShell: ApplicationShellAdapter = {
  applicationId: 'forum',
  brandKey: 'portal.brand',
  labelKey: 'common.applications.forum',
  navigation: [
    {
      id: 'forum-browse',
      labelKey: 'common.browse',
      items: [
        { labelKey: 'nav.sections', href: routes.forum, icon: 'apps' },
        { labelKey: 'nav.latest', href: routes.forumLatest, icon: 'history' },
        { labelKey: 'nav.top', href: routes.forumTop, icon: 'fire' },
        { labelKey: 'nav.activity', href: routes.forumActivity, icon: 'chart' },
        { labelKey: 'nav.search', href: routes.forumSearch, icon: 'search' },
        { labelKey: 'nav.tags', href: routes.forumTags, icon: 'tag' },
        { labelKey: 'nav.badges', href: routes.forumBadges, icon: 'trophy' },
        { labelKey: 'nav.members', href: routes.forumMembers, icon: 'users' },
        { labelKey: 'nav.staff', href: routes.forumStaff, icon: 'safe' },
        { labelKey: 'nav.statistics', href: routes.forumStatistics, icon: 'chart' },
        { labelKey: 'nav.help', href: routes.forumHelp, icon: 'book' },
      ],
    },
    {
      id: 'forum-personal',
      labelKey: 'common.mine',
      items: [
        { labelKey: 'nav.unread', href: routes.forumUnread, icon: 'notification', badgeProp: 'forum_unread.count', requiresAuthentication: true },
        { labelKey: 'nav.watching', href: routes.forumWatching, icon: 'bookmark', requiresAuthentication: true },
        { labelKey: 'nav.bookmarks', href: routes.forumBookmarks, icon: 'bookmark', requiresAuthentication: true },
        {
          labelKey: 'nav.messages',
          href: routes.forumMessages,
          badgeProp: 'messages_unread.count',
          icon: 'email',
          requiresAuthentication: true,
        },
        { labelKey: 'nav.drafts', href: routes.forumDrafts, icon: 'file', requiresAuthentication: true },
        { labelKey: 'forum.reports.caseCenter', href: routes.forumReports, icon: 'safe', requiresAuthentication: true },
        { labelKey: 'forum.reportAppeals.navigation', href: routes.forumReportAppeals, icon: 'safe', requiresAuthentication: true },
      ],
    },
  ],
  accessory: defineAsyncComponent(() => import('@/components/portal/ForumShortcuts.vue')),
}
