import assert from 'node:assert/strict'
import test from 'node:test'

import { createIdempotencyKey } from '../../app/javascript/lib/idempotency.ts'

const UUID_V4_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/

test('idempotency keys are UUIDs when randomUUID is available', () => {
  assert.match(createIdempotencyKey(), UUID_V4_PATTERN)
})

test('idempotency fallback remains a valid UUID without randomUUID', () => {
  const descriptor = Object.getOwnPropertyDescriptor(globalThis, 'crypto')
  Object.defineProperty(globalThis, 'crypto', {
    configurable: true,
    value: {
      getRandomValues(bytes: Uint8Array) {
        bytes.forEach((_, index) => {
          bytes[index] = index
        })
        return bytes
      },
    } as unknown as Crypto,
  })

  try {
    assert.match(createIdempotencyKey(), UUID_V4_PATTERN)
  } finally {
    if (descriptor) {
      Object.defineProperty(globalThis, 'crypto', descriptor)
    } else {
      Reflect.deleteProperty(globalThis, 'crypto')
    }
  }
})
