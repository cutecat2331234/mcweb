import '@/styles/applications/website-preview.css'

import type { DefineComponent } from 'vue'

import { createMcWebInertiaApplication } from '@/lib/createInertiaApplication'

const basePages = import.meta.glob<DefineComponent>([
  '../pages/Website/Pages/Show.vue',
  '../pages/Website/Articles/Show.vue',
  '../pages/WebsitePreview/DocumentFrame.vue',
])
void createMcWebInertiaApplication({
  applicationId: 'website_preview',
  pages: basePages,
  titleFallback: 'McWeb Website Preview',
  provider: true,
  progress: false,
  adapterModules: import.meta.glob(
    '../frontend-application-adapters/website_preview/**/*.ts',
    { eager: true },
  ),
  shellAdapterId: 'website_preview',
  uiAdapterId: 'mcweb_ui',
  errorBoundaryId: 'website_preview',
})
