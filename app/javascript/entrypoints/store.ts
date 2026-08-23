import '@/styles/applications/store.css'

import type { DefineComponent } from 'vue'

import { createMcWebInertiaApplication } from '@/lib/createInertiaApplication'
import { storeShell } from '@/shells/store'

const basePages = import.meta.glob<DefineComponent>([
  '../pages/Commerce/**/*.vue',
  '../pages/Payments/**/*.vue',
])
void createMcWebInertiaApplication({
  applicationId: 'store',
  pages: basePages,
  titleFallback: 'McWeb Store',
  provider: true,
  progress: false,
  adapterModules: import.meta.glob(
    '../frontend-application-adapters/store/**/*.ts',
    { eager: true },
  ),
  shellAdapter: storeShell,
  shellAdapterId: 'store',
  uiAdapterId: 'mcweb_ui',
  errorBoundaryId: 'store',
})
