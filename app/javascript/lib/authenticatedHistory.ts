const SESSION_EPOCH_KEY = 'mcweb:authenticated-history-epoch'
const SHARED_EPOCH_KEY = 'mcweb:authenticated-history-epoch'
const INERTIA_HISTORY_KEYS = ['historyKey', 'historyIv'] as const

type StorageLike = Pick<Storage, 'getItem' | 'setItem' | 'removeItem'>

function browserStorage(kind: 'localStorage' | 'sessionStorage'): StorageLike | null {
  try {
    return window[kind]
  } catch {
    return null
  }
}

function storageValue(storage: StorageLike | null, key: string): string | null {
  try {
    return storage?.getItem(key) ?? null
  } catch {
    return null
  }
}

function writeStorage(storage: StorageLike | null, key: string, value: string): void {
  try {
    storage?.setItem(key, value)
  } catch {
    // Storage can be disabled by browser policy. The remaining boundary still
    // scrubs the active history entry and whichever storage is available.
  }
}

function removeStorage(storage: StorageLike | null, key: string): void {
  try {
    storage?.removeItem(key)
  } catch {
    // Treat unavailable storage as already cleared.
  }
}

function newEpoch(): string {
  if (typeof window.crypto?.randomUUID === 'function') return window.crypto.randomUUID()
  const bytes = window.crypto?.getRandomValues?.(new Uint32Array(4))
  return bytes
    ? Array.from(bytes, (value) => value.toString(16).padStart(8, '0')).join('')
    : `${Date.now()}:${Math.random()}`
}

function clearInertiaHistoryEncryption(): void {
  const sessionStorage = browserStorage('sessionStorage')
  for (const key of INERTIA_HISTORY_KEYS) removeStorage(sessionStorage, key)
}

function scrubCurrentHistoryEntry(): void {
  try {
    window.history.replaceState(
      { mcwebSessionInvalidated: true },
      document.title,
      window.location.href,
    )
  } catch {
    // The subsequent full-document navigation remains the final boundary.
  }
}

function safeDestination(value: string): URL | null {
  try {
    const destination = new URL(value, window.location.href)
    return destination.origin === window.location.origin ? destination : null
  } catch {
    return null
  }
}

export function invalidateAuthenticatedHistory(): void {
  const epoch = newEpoch()
  writeStorage(browserStorage('sessionStorage'), SESSION_EPOCH_KEY, epoch)
  writeStorage(browserStorage('localStorage'), SHARED_EPOCH_KEY, epoch)
  clearInertiaHistoryEncryption()
  scrubCurrentHistoryEntry()
}

export function installAuthenticatedHistoryBoundary(signedOutPath: string): VoidFunction {
  const destination = safeDestination(signedOutPath)
  if (!destination) throw new Error('Authenticated history boundary requires a same-origin URL')

  const initialSessionEpoch = storageValue(browserStorage('sessionStorage'), SESSION_EPOCH_KEY)
  const initialSharedEpoch = storageValue(browserStorage('localStorage'), SHARED_EPOCH_KEY)
  let invalidating = false

  const epochChanged = () => (
    storageValue(browserStorage('sessionStorage'), SESSION_EPOCH_KEY) !== initialSessionEpoch
    || storageValue(browserStorage('localStorage'), SHARED_EPOCH_KEY) !== initialSharedEpoch
  )
  const leaveInvalidDocument = () => {
    if (invalidating || !epochChanged()) return
    invalidating = true
    clearInertiaHistoryEncryption()
    scrubCurrentHistoryEntry()
    window.location.replace(destination.href)
  }
  const onStorage = (event: StorageEvent) => {
    if (event.key === SHARED_EPOCH_KEY) leaveInvalidDocument()
  }
  const onPageShow = () => leaveInvalidDocument()

  window.addEventListener('storage', onStorage)
  window.addEventListener('pageshow', onPageShow)
  return () => {
    window.removeEventListener('storage', onStorage)
    window.removeEventListener('pageshow', onPageShow)
  }
}
