import '@/styles/applications/forum.css'

import type { DefineComponent } from 'vue'

import { createMcWebInertiaApplication } from '@/lib/createInertiaApplication'
import { forumShell } from '@/shells/forum'
import AppProvider from '@/components/AppProvider.vue'

const basePages = import.meta.glob<DefineComponent>('../pages/Community/**/*.vue')

void createMcWebInertiaApplication({
  applicationId: 'forum',
  pages: basePages,
  titleFallback: 'McWeb Forum',
  providerComponent: AppProvider,
  progress: false,
  adapterModules: import.meta.glob(
    '../frontend-application-adapters/forum/**/*.ts',
    { eager: true },
  ),
  shellAdapter: forumShell,
  shellAdapterId: 'forum',
  uiAdapterId: 'mcweb_ui',
  errorBoundaryId: 'forum',
})
