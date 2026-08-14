import { createI18n } from 'vue-i18n'
import {
  missingTranslation,
  normalizeAppLocale,
  type AppLocale,
} from './i18nRuntime'
import { writeSharedAppLocale } from './localePreference'

export {
  MISSING_TRANSLATION_EVENT,
  normalizeAppLocale,
  type AppLocale,
  type MissingTranslationDetail,
} from './i18nRuntime'

const localeLoaders = {
  'zh-CN': () => import('@/locales/zh-CN'),
  en: () => import('@/locales/en'),
} satisfies Record<AppLocale, () => Promise<{ default: Record<string, unknown> }>>

type AppMessages = Awaited<ReturnType<(typeof localeLoaders)[AppLocale]>>['default']

const loadedMessages = new Map<AppLocale, AppMessages>()
const localeSyncGenerations = new WeakMap<object, number>()

async function loadLocaleMessages(locale: AppLocale): Promise<AppMessages> {
  const cached = loadedMessages.get(locale)
  if (cached) return cached

  const messages = (await localeLoaders[locale]()).default
  loadedMessages.set(locale, messages)
  return messages
}

export function preloadAppLocale(locale: unknown): Promise<AppMessages> {
  return loadLocaleMessages(normalizeAppLocale(locale))
}

export async function createAppI18n(locale: AppLocale = 'zh-CN') {
  const initialLocale = normalizeAppLocale(locale)
  const messages = await loadLocaleMessages(initialLocale)
  writeSharedAppLocale(initialLocale)

  return createI18n({
    legacy: false,
    globalInjection: true,
    locale: initialLocale,
    // A fallback language would force every visitor to download a second,
    // otherwise unused locale bundle. Missing-copy checks run in CI instead.
    fallbackLocale: false,
    missingWarn: false,
    fallbackWarn: false,
    missing: (missingLocale, key, _instance, type) => (
      missingTranslation(String(missingLocale), String(key), type)
    ),
    messages: {
      [initialLocale]: messages,
    },
  })
}

export type AppI18n = Awaited<ReturnType<typeof createAppI18n>>

export async function syncI18nLocale(i18n: AppI18n, locale: unknown): Promise<boolean> {
  const next = normalizeAppLocale(locale)
  const syncTarget = i18n as object
  const generation = (localeSyncGenerations.get(syncTarget) ?? 0) + 1
  localeSyncGenerations.set(syncTarget, generation)

  let messages: AppMessages | null = null
  if (!i18n.global.availableLocales.includes(next)) {
    messages = await loadLocaleMessages(next)
  }
  if (localeSyncGenerations.get(syncTarget) !== generation) return false

  if (messages) i18n.global.setLocaleMessage(next, messages)
  if (i18n.global.locale.value !== next) {
    i18n.global.locale.value = next
  }
  if (typeof document !== 'undefined') {
    document.documentElement.lang = next
  }
  writeSharedAppLocale(next)
  return true
}

// Merge DB-backed admin "phrase overrides" (shared as a nested Inertia prop for
// the current locale) on top of the static locale messages, so overrides win.
export function applyPhraseOverrides(i18n: AppI18n, locale: unknown, overrides: unknown) {
  if (!overrides || typeof overrides !== 'object') return
  const target = normalizeAppLocale(locale)
  i18n.global.mergeLocaleMessage(target, overrides as Record<string, unknown>)
}
