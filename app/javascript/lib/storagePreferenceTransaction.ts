export type StoragePreferenceTransaction = {
  commit: () => void
  rollback: () => void
}

type StorageSnapshot = {
  storage: Storage | null
  value: string | null
}

function captureStorage(key: string): StorageSnapshot {
  if (typeof window === 'undefined') return { storage: null, value: null }

  try {
    return {
      storage: window.localStorage,
      value: window.localStorage.getItem(key),
    }
  } catch {
    return { storage: null, value: null }
  }
}

export function beginStoragePreferenceTransaction(
  key: string,
  value: string,
): StoragePreferenceTransaction {
  const snapshot = captureStorage(key)
  let settled = false

  try {
    snapshot.storage?.setItem(key, value)
  } catch {
    // Storage can become unavailable between capture and write.
  }

  return {
    commit() {
      settled = true
    },
    rollback() {
      if (settled || !snapshot.storage) return

      try {
        if (snapshot.value === null) {
          snapshot.storage.removeItem(key)
        } else {
          snapshot.storage.setItem(key, snapshot.value)
        }
      } catch {
        // Storage can become unavailable while a request is in flight.
      } finally {
        settled = true
      }
    },
  }
}
