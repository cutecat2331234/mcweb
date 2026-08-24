import { computed, watch } from 'vue'
import {
  createI18n,
  useI18n,
  type ComposerOptions,
  type DefineLocaleMessage,
  type I18n,
  type I18nOptions,
} from 'vue-i18n'
import {
  addI18nMessages,
  useLocale as setArcoLocale,
} from '@arco-design/web-vue/es/locale/index.js'
import arcoEnUS from '@arco-design/web-vue/es/locale/lang/en-us.js'
import arcoZhCN from '@arco-design/web-vue/es/locale/lang/zh-cn.js'
import type { ArcoLang } from '@arco-design/web-vue/es/locale/interface.js'
import {
  mergeLocaleMessages,
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

const ARCO_LOCALES = {
  'zh-CN': arcoZhCN,
  en: arcoEnUS,
} satisfies Record<AppLocale, ArcoLang>

addI18nMessages(
  {
    [arcoZhCN.locale]: arcoZhCN,
    [arcoEnUS.locale]: arcoEnUS,
  },
  { overwrite: true },
)

export function resolveArcoLocale(locale: unknown): ArcoLang {
  return ARCO_LOCALES[normalizeAppLocale(locale)]
}

export function syncArcoLocale(locale: unknown): ArcoLang {
  const next = resolveArcoLocale(locale)
  // Static services such as Modal.confirm render outside the component tree.
  setArcoLocale(next.locale)
  return next
}

export function useArcoLocale() {
  const { locale } = useI18n()
  const arcoLocale = computed(() => resolveArcoLocale(locale.value))

  watch(
    locale,
    (next) => {
      syncArcoLocale(next)
    },
    { immediate: true },
  )

  return arcoLocale
}

type LocaleDomainLoader = () => Promise<{ default: Record<string, unknown> }>

const localeDomainLoaders: Record<AppLocale, Record<string, LocaleDomainLoader>> = {
  'zh-CN': {
    core: () => import('@/locales/domains/zh-CN/core'),
    website: () => import('@/locales/domains/zh-CN/website'),
    forum: () => import('@/locales/domains/zh-CN/forum'),
    store: () => import('@/locales/domains/zh-CN/store'),
    account: () => import('@/locales/domains/zh-CN/account'),
    staff: () => import('@/locales/domains/zh-CN/staff'),
    admin: () => import('@/locales/domains/zh-CN/admin'),
  },
  en: {
    core: () => import('@/locales/domains/en/core'),
    website: () => import('@/locales/domains/en/website'),
    forum: () => import('@/locales/domains/en/forum'),
    store: () => import('@/locales/domains/en/store'),
    account: () => import('@/locales/domains/en/account'),
    staff: () => import('@/locales/domains/en/staff'),
    admin: () => import('@/locales/domains/en/admin'),
  },
}

type AppMessages = Record<string, unknown>
type AppMessageSchema = DefineLocaleMessage
type AppLocaleMessageCatalog = Record<AppLocale, AppMessageSchema>
type AppI18nSchema = { message: AppMessageSchema }
type AppI18nOptions = I18nOptions<
  AppI18nSchema,
  AppLocale,
  ComposerOptions<AppI18nSchema, AppLocale>
> & {
  legacy: false
  locale: AppLocale
  messages: AppLocaleMessageCatalog
}

export type AppI18n = I18n<AppLocaleMessageCatalog, {}, {}, AppLocale, false>

function vueI18nMessageSchema(messages: AppMessages): AppMessageSchema {
  // Locale modules are application-owned static dictionaries. Their loader
  // deliberately exposes unknown values until they cross this library boundary.
  return messages as AppMessageSchema
}

const loadedDomainMessages = new Map<string, AppMessages>()
const localeSyncGenerations = new WeakMap<object, number>()
const localeDomainsByI18n = new WeakMap<object, readonly string[]>()

export function registerFrontendLocaleDomain(
  domain: string,
  loaders: Record<AppLocale, LocaleDomainLoader>,
): VoidFunction {
  if (!/^[a-z][a-z0-9_]*$/.test(domain)) throw new Error(`Invalid locale domain: ${domain}`)
  for (const locale of Object.keys(localeDomainLoaders) as AppLocale[]) {
    if (!loaders[locale]) throw new Error(`Locale domain ${domain} has no ${locale} loader`)
    if (Object.hasOwn(localeDomainLoaders[locale], domain)) {
      throw new Error(`Locale domain is already registered: ${domain}`)
    }
  }
  for (const locale of Object.keys(localeDomainLoaders) as AppLocale[]) {
    localeDomainLoaders[locale][domain] = loaders[locale]
  }
  let registered = true
  return () => {
    if (!registered) return
    registered = false
    for (const locale of Object.keys(localeDomainLoaders) as AppLocale[]) {
      if (localeDomainLoaders[locale][domain] === loaders[locale]) {
        delete localeDomainLoaders[locale][domain]
        loadedDomainMessages.delete(`${locale}:${domain}`)
      }
    }
  }
}

function localeDomains(values: readonly string[]): readonly string[] {
  const available = localeDomainLoaders.en
  const domains = values.map((value) => {
    if (!Object.hasOwn(available, value)) throw new Error(`Unknown locale domain: ${value}`)
    return value
  })
  return [...new Set(domains)]
}

async function loadLocaleDomain(locale: AppLocale, domain: string): Promise<AppMessages> {
  const cacheKey = `${locale}:${domain}`
  const cached = loadedDomainMessages.get(cacheKey)
  if (cached) return cached
  const messages = (await localeDomainLoaders[locale][domain]()).default
  loadedDomainMessages.set(cacheKey, messages)
  return messages
}

async function loadLocaleMessages(
  locale: AppLocale,
  domains: readonly string[],
): Promise<AppMessages> {
  return mergeLocaleMessages(await Promise.all(
    domains.map((domain) => loadLocaleDomain(locale, domain)),
  ))
}

export function preloadAppLocale(
  locale: unknown,
  domains: readonly string[] = ['core'],
): Promise<AppMessages> {
  return loadLocaleMessages(normalizeAppLocale(locale), localeDomains(domains))
}

export async function createAppI18n(
  locale: AppLocale = 'zh-CN',
  domainNames: readonly string[] = ['core'],
): Promise<AppI18n> {
  const initialLocale = normalizeAppLocale(locale)
  const domains = localeDomains(domainNames)
  const messages = await loadLocaleMessages(initialLocale, domains)
  // The type describes every locale that can be installed into this instance;
  // the runtime object intentionally contains only the active locale at boot.
  const initialMessages = {
    [initialLocale]: vueI18nMessageSchema(messages),
  } as AppLocaleMessageCatalog
  writeSharedAppLocale(initialLocale)

  const options: AppI18nOptions = {
    legacy: false,
    globalInjection: true,
    locale: initialLocale,
    // Keep each application on its canonical locale. In particular, Vue i18n
    // must not turn a zh-CN miss into an implicit lookup against a non-existent
    // "zh" locale, nor download another language domain as a fallback.
    fallbackLocale: {
      'zh-CN': [],
      en: [],
    },
    missingWarn: false,
    fallbackWarn: false,
    missing: (missingLocale, key, _instance, type) => (
      missingTranslation(String(missingLocale), String(key), type)
    ),
    messages: initialMessages,
  }
  const i18n = createI18n<false, AppI18nOptions>(options)
  localeDomainsByI18n.set(i18n as object, domains)
  return i18n
}

export async function syncI18nLocale(i18n: AppI18n, locale: unknown): Promise<boolean> {
  const next = normalizeAppLocale(locale)
  const syncTarget = i18n as object
  const generation = (localeSyncGenerations.get(syncTarget) ?? 0) + 1
  localeSyncGenerations.set(syncTarget, generation)

  let messages: AppMessages | null = null
  if (!i18n.global.availableLocales.includes(next)) {
    messages = await loadLocaleMessages(
      next,
      localeDomainsByI18n.get(syncTarget) ?? ['core'],
    )
  }
  if (localeSyncGenerations.get(syncTarget) !== generation) return false

  if (messages) i18n.global.setLocaleMessage(next, vueI18nMessageSchema(messages))
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
  i18n.global.mergeLocaleMessage(
    target,
    vueI18nMessageSchema(overrides as Record<string, unknown>),
  )
}
