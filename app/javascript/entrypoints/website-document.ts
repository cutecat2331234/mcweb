import '@/styles/applications/website.css'

import type { DefineComponent } from 'vue'

import { createMcWebInertiaApplication } from '@/lib/createInertiaApplication'
import AppProvider from '@/components/AppProvider.vue'

const basePages = import.meta.glob<DefineComponent>([
  '../pages/Website/**/*.vue',
  '../pages/Plugins/**/*.vue',
])
void createMcWebInertiaApplication({
  applicationId: 'website',
  pages: basePages,
  titleFallback: 'McWeb',
  providerComponent: AppProvider,
  progress: false,
  adapterModules: import.meta.glob(
    '../frontend-application-adapters/website/**/*.ts',
    { eager: true },
  ),
  shellAdapterId: 'website',
  uiAdapterId: 'website',
  errorBoundaryId: 'website',
})
