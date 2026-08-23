import type { FrontendDraftContract } from '@/lib/frontendApplications'

const FRONTEND_DRAFT_ADAPTER = Symbol('mcweb-frontend-draft-adapter')

export type FrontendDraftContext = Readonly<{
  userId: string | number
  resourceId: string | number
}>

export type FrontendDraftEnvelope<T> = Readonly<{
  namespace: string
  version: number
  userId: string
  resourceId: string
  savedAt: string
  payload: T
}>

export type FrontendDraftKeyIdentity = Readonly<{
  namespace: string
  version: number
  userId: string
  resourceId: string
}>

export type FrontendDraftKeyStrategy = Readonly<{
  build: (
    context: FrontendDraftContext,
    contract: FrontendDraftContract,
  ) => string
  parse: (key: string) => FrontendDraftKeyIdentity | null
}>

export type FrontendDraftPersistence<T> = Readonly<{
  read: (key: string) => Promise<FrontendDraftEnvelope<T> | null>
  write: (key: string, value: FrontendDraftEnvelope<T>) => Promise<void>
  remove: (key: string) => Promise<void>
}>

export type FrontendDraftAdapter<T = unknown> = Readonly<{
  contract: FrontendDraftContract
  storageKey: (context: FrontendDraftContext) => string
  restore: (context: FrontendDraftContext) => Promise<T | null>
  persist: (context: FrontendDraftContext, payload: T) => Promise<void>
  clear: (context: FrontendDraftContext) => Promise<void>
  submitted: (context: FrontendDraftContext) => Promise<void>
  readonly [FRONTEND_DRAFT_ADAPTER]: true
}>

type DefineFrontendDraftAdapterOptions<T> = Readonly<{
  contract: FrontendDraftContract
  persistence: FrontendDraftPersistence<T>
  recoverLegacy?: (context: FrontendDraftContext) => Promise<T | null>
  keyStrategy?: FrontendDraftKeyStrategy
}>

const installedDraftAdapters = new Map<string, FrontendDraftAdapter>()

function contextValue(value: string | number, field: string): string {
  const normalized = String(value).trim()
  if (!normalized) throw new Error(`Frontend draft ${field} must not be empty`)
  return normalized
}

function normalizedContext(context: FrontendDraftContext): Readonly<{
  userId: string
  resourceId: string
}> {
  return {
    userId: contextValue(context.userId, 'userId'),
    resourceId: contextValue(context.resourceId, 'resourceId'),
  }
}

function draftIdentity(
  contract: FrontendDraftContract,
  context: FrontendDraftContext,
): FrontendDraftKeyIdentity {
  const identity = normalizedContext(context)
  return {
    namespace: contract.keyNamespace,
    version: contract.version,
    userId: identity.userId,
    resourceId: identity.resourceId,
  }
}

function decodeKeyPart(value: string): string | null {
  try {
    return decodeURIComponent(value)
  } catch {
    return null
  }
}

export const canonicalFrontendDraftKeyStrategy: FrontendDraftKeyStrategy = Object.freeze({
  build(context, contract) {
    const identity = draftIdentity(contract, context)
    return [
      'mcweb-draft',
      encodeURIComponent(identity.namespace),
      `v${identity.version}`,
      encodeURIComponent(identity.userId),
      encodeURIComponent(identity.resourceId),
    ].join('/')
  },
  parse(key) {
    const parts = key.split('/')
    if (parts.length !== 5 || parts[0] !== 'mcweb-draft' || !/^v[1-9]\d*$/.test(parts[2])) {
      return null
    }
    const namespace = decodeKeyPart(parts[1])
    const userId = decodeKeyPart(parts[3])
    const resourceId = decodeKeyPart(parts[4])
    if (!namespace || !userId || !resourceId) return null
    return {
      namespace,
      version: Number(parts[2].slice(1)),
      userId,
      resourceId,
    }
  },
})

function validatedStorageKey(
  strategy: FrontendDraftKeyStrategy,
  contract: FrontendDraftContract,
  context: FrontendDraftContext,
): string {
  const key = strategy.build(context, contract)
  const expected = draftIdentity(contract, context)
  const parsed = key && !/[\u0000-\u001f\u007f]/.test(key) ? strategy.parse(key) : null
  if (!parsed
    || parsed.namespace !== expected.namespace
    || parsed.version !== expected.version
    || parsed.userId !== expected.userId
    || parsed.resourceId !== expected.resourceId) {
    throw new Error('Frontend draft key strategy does not preserve namespace/version/user/resource identity')
  }
  return key
}

function envelopeMatches<T>(
  envelope: FrontendDraftEnvelope<T>,
  contract: FrontendDraftContract,
  context: FrontendDraftContext,
): boolean {
  const identity = normalizedContext(context)
  return envelope.namespace === contract.keyNamespace
    && envelope.version === contract.version
    && envelope.userId === identity.userId
    && envelope.resourceId === identity.resourceId
}

export function defineFrontendDraftAdapter<T>({
  contract,
  persistence,
  recoverLegacy,
  keyStrategy = canonicalFrontendDraftKeyStrategy,
}: DefineFrontendDraftAdapterOptions<T>): FrontendDraftAdapter<T> {
  const frozenContract = Object.freeze({ ...contract })
  const keyFor = (context: FrontendDraftContext) => validatedStorageKey(
    keyStrategy,
    frozenContract,
    context,
  )

  const persist = async (context: FrontendDraftContext, payload: T) => {
    const identity = normalizedContext(context)
    await persistence.write(keyFor(context), {
      namespace: frozenContract.keyNamespace,
      version: frozenContract.version,
      userId: identity.userId,
      resourceId: identity.resourceId,
      savedAt: new Date().toISOString(),
      payload,
    })
  }

  const adapter: FrontendDraftAdapter<T> = {
    contract: frozenContract,
    storageKey: keyFor,
    async restore(context) {
      const key = keyFor(context)
      const envelope = await persistence.read(key)
      if (envelope) {
        if (!envelopeMatches(envelope, frozenContract, context)) {
          await persistence.remove(key)
          return null
        }
        return envelope.payload
      }

      const recovered = await recoverLegacy?.(context)
      if (recovered === undefined || recovered === null) return null
      await persist(context, recovered)
      return recovered
    },
    persist,
    clear: (context) => persistence.remove(keyFor(context)),
    submitted: (context) => persistence.remove(keyFor(context)),
    [FRONTEND_DRAFT_ADAPTER]: true,
  }
  return Object.freeze(adapter)
}

export function isFrontendDraftAdapter(value: unknown): value is FrontendDraftAdapter {
  return Boolean(
    value
      && typeof value === 'object'
      && (value as Partial<FrontendDraftAdapter>)[FRONTEND_DRAFT_ADAPTER] === true,
  )
}

export function installFrontendDraftAdapter(
  applicationId: string,
  contributionId: string,
  adapter: FrontendDraftAdapter,
): VoidFunction {
  const key = `${applicationId}:${contributionId}`
  if (installedDraftAdapters.has(key)) {
    throw new Error(`Frontend draft adapter is already installed: ${key}`)
  }
  installedDraftAdapters.set(key, adapter)
  return () => {
    if (installedDraftAdapters.get(key) === adapter) installedDraftAdapters.delete(key)
  }
}

export function frontendDraftAdapter(
  applicationId: string,
  contributionId: string,
): FrontendDraftAdapter | null {
  return installedDraftAdapters.get(`${applicationId}:${contributionId}`) ?? null
}

export function browserLocalStorageDraftPersistence<T>(): FrontendDraftPersistence<T> {
  const memoryFallback = new Map<string, FrontendDraftEnvelope<T>>()
  return {
    async read(key) {
      let raw: string | null = null
      try {
        raw = window.localStorage.getItem(key)
      } catch {
        return memoryFallback.get(key) ?? null
      }
      if (!raw) return memoryFallback.get(key) ?? null
      try {
        return JSON.parse(raw) as FrontendDraftEnvelope<T>
      } catch {
        try {
          window.localStorage.removeItem(key)
        } catch {
          // Storage may become unavailable after a successful read.
        }
        return null
      }
    },
    async write(key, value) {
      memoryFallback.set(key, value)
      try {
        window.localStorage.setItem(key, JSON.stringify(value))
      } catch {
        // Preserve a session-local recovery copy when durable storage is unavailable.
      }
    },
    async remove(key) {
      memoryFallback.delete(key)
      try {
        window.localStorage.removeItem(key)
      } catch {
        // The in-memory copy has still been cleared.
      }
    },
  }
}
