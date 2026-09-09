import { shallowRef, type Component, type ShallowRef } from 'vue'

export type ApplicationStatusSurfaceKind = 'portal' | 'admin'

type StatusSurfacePage = {
  props?: Record<string, unknown>
}

type StatusSurface = {
  component: ShallowRef<Component | null>
  load: () => Promise<void>
}

function createStatusSurface(
  loader: () => Promise<{ default: Component }>,
): StatusSurface {
  const component = shallowRef<Component | null>(null)
  let pending: Promise<void> | null = null

  return {
    component,
    async load() {
      if (component.value) return
      const loading = pending ??= loader()
        .then((module) => {
          component.value = module.default
        })
        .finally(() => {
          pending = null
        })
      await loading
    },
  }
}

const developerModeBanner = createStatusSurface(
  () => import('@/components/application-shell/ApplicationDeveloperModeBanner.vue'),
)
const portalFlashMessages = createStatusSurface(
  () => import('@/components/portal/FlashMessages.vue'),
)
const portalAnnouncements = createStatusSurface(
  () => import('@/components/portal/PortalAnnouncements.vue'),
)
const adminFlashMessages = createStatusSurface(
  () => import('@/components/admin/AdminFlashMessages.vue'),
)
const pluginUiSlots = createStatusSurface(
  () => import('@/components/plugins/PluginUiSlots.vue'),
)

function record(value: unknown): Record<string, unknown> | undefined {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown>
    : undefined
}

function hasDeveloperModeBanner(page?: StatusSurfacePage): boolean {
  return record(page?.props?.developer_mode)?.enabled === true
}

function hasFlashMessages(page?: StatusSurfacePage): boolean {
  const flash = record(page?.props?.flash)
  return Boolean(flash?.notice || flash?.alert)
}

function hasPortalAnnouncements(applicationId: string, page?: StatusSurfacePage): boolean {
  if (applicationId !== 'forum') return false
  const announcements = page?.props?.global_announcements
  const notices = page?.props?.forum_notices
  return (Array.isArray(announcements) && announcements.length > 0)
    || (Array.isArray(notices) && notices.length > 0)
}

function hasPluginUiSlots(page?: StatusSurfacePage): boolean {
  const contributions = record(page?.props?.plugin_contributions)
  const slots = contributions?.ui_slots
  return Array.isArray(slots) && slots.length > 0
}

export async function prepareApplicationStatusSurfaces(
  kind: ApplicationStatusSurfaceKind | false,
  applicationId: string,
  page?: StatusSurfacePage,
): Promise<void> {
  if (!kind) return

  const pending: Promise<void>[] = []
  if (hasDeveloperModeBanner(page)) pending.push(developerModeBanner.load())

  if (kind === 'portal') {
    if (hasFlashMessages(page)) pending.push(portalFlashMessages.load())
    if (hasPortalAnnouncements(applicationId, page)) pending.push(portalAnnouncements.load())
  } else {
    if (hasFlashMessages(page)) pending.push(adminFlashMessages.load())
    if (hasPluginUiSlots(page)) pending.push(pluginUiSlots.load())
  }

  await Promise.all(pending)
}

export function usePortalApplicationStatusSurfaces() {
  return {
    developerModeBanner: developerModeBanner.component,
    flashMessages: portalFlashMessages.component,
    portalAnnouncements: portalAnnouncements.component,
  }
}

export function useAdminApplicationStatusSurfaces() {
  return {
    developerModeBanner: developerModeBanner.component,
    flashMessages: adminFlashMessages.component,
    pluginUiSlots: pluginUiSlots.component,
  }
}
