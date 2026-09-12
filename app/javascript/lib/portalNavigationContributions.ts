export type PortalApplicationDestination = Readonly<{
  id: string
  labelKey: string
  href: string
  icon: string
  requiresAuthentication?: boolean
}>

export type PortalNavigationItem = { href: string; label: string; badge: number; icon?: string }
export type PortalNavigationGroup = { id: string; label: string; items: PortalNavigationItem[] }
export type PortalNavigationDestination = { id: string; label: string; href: string; icon: string; badge?: number }

// Editions contribute link metadata, never another application's pages or state.
const modules = import.meta.glob<{ default: PortalApplicationDestination }>(
  '../navigation-contributions/*.ts',
  { eager: true },
)

export const portalNavigationContributions = Object.values(modules).map((module) => module.default)
