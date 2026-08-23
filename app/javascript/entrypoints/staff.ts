import '@/styles/applications/staff.css'

import type { DefineComponent } from 'vue'

import { createMcWebInertiaApplication } from '@/lib/createInertiaApplication'
import { staffShell } from '@/shells/staff'

const basePages = import.meta.glob<DefineComponent>([
  '../pages/Staff/Dashboard/**/*.vue',
  '../pages/Staff/Forum/Approvals/**/*.vue',
  '../pages/Staff/ModerationCases/**/*.vue',
  '../pages/Staff/ReportAppeals/**/*.vue',
])
void createMcWebInertiaApplication({
  applicationId: 'staff',
  pages: basePages,
  titleFallback: 'McWeb Staff',
  provider: false,
  progress: { color: '#38bdf8' },
  adapterModules: import.meta.glob(
    '../frontend-application-adapters/staff/**/*.ts',
    { eager: true },
  ),
  shellAdapter: staffShell,
  shellAdapterId: 'staff',
  uiAdapterId: 'mcweb_ui',
  errorBoundaryId: 'staff',
})
