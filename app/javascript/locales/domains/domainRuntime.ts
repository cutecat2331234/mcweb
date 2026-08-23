export const LOCALE_DOMAIN_KEYS = {
  core: ['common', 'locale', 'components'],
  website: ['website'],
  forum: ['nav', 'portal', 'breadcrumb', 'shortcuts', 'forum', 'userProfile', 'checkIn'],
  store: ['nav', 'portal', 'breadcrumb', 'commerce', 'payments'],
  account: ['nav', 'portal', 'breadcrumb', 'accountCenter', 'accountNotifications', 'auth', 'identity', 'minecraft'],
  staff: ['nav', 'staffWorkspace'],
  admin: ['admin', 'adminMinecraft', 'adminForum', 'commerce', 'forum', 'identity', 'minecraft', 'payments', 'website'],
} as const

export type LocaleDomain = keyof typeof LOCALE_DOMAIN_KEYS

export function localeDomainMessages(
  messages: Record<string, unknown>,
  domain: LocaleDomain,
): Record<string, unknown> {
  return Object.fromEntries(
    LOCALE_DOMAIN_KEYS[domain]
      .filter((key) => Object.hasOwn(messages, key))
      .map((key) => [key, messages[key]]),
  )
}
