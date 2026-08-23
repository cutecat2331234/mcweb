import '@/styles/applications/account.css'

import type { DefineComponent } from 'vue'

import { createMcWebInertiaApplication } from '@/lib/createInertiaApplication'
import { accountShell } from '@/shells/account'

const basePages = import.meta.glob<DefineComponent>([
  '../pages/Account/**/*.vue',
  '../pages/Identity/**/*.vue',
  '../pages/Minecraft/**/*.vue',
])
void createMcWebInertiaApplication({
  applicationId: 'account',
  pages: basePages,
  titleFallback: 'McWeb Account',
  provider: true,
  progress: false,
  adapterModules: import.meta.glob(
    '../frontend-application-adapters/account/**/*.ts',
    { eager: true },
  ),
  shellAdapter: accountShell,
  shellAdapterId: 'account',
  uiAdapterId: 'mcweb_ui',
  errorBoundaryId: 'account',
})
