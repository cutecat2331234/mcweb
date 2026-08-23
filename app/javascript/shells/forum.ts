import { defineAsyncComponent } from 'vue'

import type { ApplicationShellAdapter } from '@/lib/applicationShell'
import { routes } from '@/lib/routes'

export const forumShell: ApplicationShellAdapter = {
  applicationId: 'forum',
  brandKey: 'portal.brand',
  navigation: [
    {
      id: 'forum-browse',
      labelKey: 'common.browse',
      items: [
        { labelKey: 'nav.latest', href: routes.forumLatest },
        { labelKey: 'nav.sections', href: routes.forum },
        { labelKey: 'nav.top', href: routes.forumTop },
        { labelKey: 'nav.activity', href: routes.forumActivity },
        { labelKey: 'nav.search', href: routes.forumSearch },
        { labelKey: 'nav.tags', href: routes.forumTags },
      ],
    },
    {
      id: 'forum-personal',
      labelKey: 'common.mine',
      items: [
        { labelKey: 'nav.unread', href: routes.forumUnread, requiresAuthentication: true },
        { labelKey: 'nav.watching', href: routes.forumWatching, requiresAuthentication: true },
        { labelKey: 'nav.bookmarks', href: routes.forumBookmarks, requiresAuthentication: true },
        { labelKey: 'nav.messages', href: routes.forumMessages, requiresAuthentication: true },
      ],
    },
  ],
  accessory: defineAsyncComponent(() => import('@/components/portal/ForumShortcuts.vue')),
}
