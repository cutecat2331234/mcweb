import '@/styles/applications/admin.css'

import type { DefineComponent } from 'vue'

import { createMcWebInertiaApplication } from '@/lib/createInertiaApplication'
import { adminShell } from '@/shells/admin'

const basePages = import.meta.glob<DefineComponent>([
  '../pages/Admin/ArcoDemo/**/*.vue',
  '../pages/Admin/AuditLogs/**/*.vue',
  '../pages/Admin/Dashboard/**/*.vue',
  '../pages/Admin/Forum/**/*.vue',
  '../pages/Admin/Frontend/**/*.vue',
  '../pages/Admin/Generic/**/*.vue',
  '../pages/Admin/Minecraft/**/*.vue',
  '../pages/Admin/Plugins/**/*.vue',
  '../pages/Admin/Roles/**/*.vue',
  '../pages/Admin/Store/**/*.vue',
  '../pages/Admin/System/**/*.vue',
  '../pages/Admin/Users/**/*.vue',
  '../pages/Admin/Website/**/*.vue',
  '../pages/Admin/DashboardProDemo.vue',
])
void createMcWebInertiaApplication({
  applicationId: 'admin',
  pages: basePages,
  titleFallback: 'McWeb Admin',
  provider: false,
  progress: { color: '#38bdf8' },
  adapterModules: import.meta.glob(
    '../frontend-application-adapters/admin/**/*.ts',
    { eager: true },
  ),
  shellAdapter: adminShell,
  shellAdapterId: 'admin',
  uiAdapterId: 'mcweb_ui',
  errorBoundaryId: 'admin',
})
