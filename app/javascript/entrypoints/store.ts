import '@/styles/applications/store.css'

import type { DefineComponent } from 'vue'

import { createMcWebInertiaApplication } from '@/lib/createInertiaApplication'
import { storeShell } from '@/shells/store'
import AppProvider from '@/components/AppProvider.vue'

const basePages = import.meta.glob<DefineComponent>([
  '../pages/Commerce/**/*.vue',
  '../pages/Payments/**/*.vue',
])
void createMcWebInertiaApplication({
  applicationId: 'store',
  pages: basePages,
  titleFallback: 'McWeb Store',
  providerComponent: AppProvider,
  progress: false,
  adapterModules: import.meta.glob(
    '../frontend-application-adapters/store/**/*.ts',
    { eager: true },
  ),
  shellAdapter: storeShell,
  shellAdapterId: 'store',
  uiAdapterId: 'mcweb_ui',
  errorBoundaryId: 'store',
  statusSurfaceKind: 'portal',
})
