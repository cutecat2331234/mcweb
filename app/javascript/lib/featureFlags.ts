export type FeatureId = 'forum' | 'store' | 'website_blog' | 'minecraft'

export type FeatureFlagsMap = Record<FeatureId, boolean>

export const defaultFeatureFlags = (): FeatureFlagsMap => ({
  forum: true,
  store: true,
  website_blog: true,
  minecraft: true,
})

export function resolveFeatureFlags(raw?: Partial<FeatureFlagsMap> | null): FeatureFlagsMap {
  const defaults = defaultFeatureFlags()
  if (!raw) return defaults

  return {
    forum: raw.forum !== false,
    store: raw.store !== false,
    website_blog: raw.website_blog !== false,
    minecraft: raw.minecraft !== false,
  }
}

export function isBlogHref(href: string): boolean {
  return href === '/blog' || href.startsWith('/blog/')
}
