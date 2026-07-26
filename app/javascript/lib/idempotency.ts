export function createIdempotencyKey(): string {
  if (globalThis.crypto?.randomUUID) {
    return globalThis.crypto.randomUUID()
  }

  return `request-${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`
}
