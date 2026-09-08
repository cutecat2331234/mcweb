import assert from 'node:assert/strict'
import test from 'node:test'

import {
  installAuthenticatedHistoryBoundary,
  invalidateAuthenticatedHistory,
  invalidatePreviouslyAuthenticatedHistory,
} from '../../app/javascript/lib/authenticatedHistory.ts'

class MemoryStorage {
  private readonly values = new Map<string, string>()

  getItem(key: string): string | null {
    return this.values.get(key) ?? null
  }

  setItem(key: string, value: string): void {
    this.values.set(key, value)
  }

  removeItem(key: string): void {
    this.values.delete(key)
  }
}

type BrowserHarness = {
  localStorage: MemoryStorage
  sessionStorage: MemoryStorage
  historyStates: unknown[]
  replacements: string[]
  dispatchStorage: (key: string) => void
  dispatchPageShow: () => void
  restore: () => void
}

function installBrowserHarness(options: { storageThrows?: boolean } = {}): BrowserHarness {
  const previousWindow = Object.getOwnPropertyDescriptor(globalThis, 'window')
  const previousDocument = Object.getOwnPropertyDescriptor(globalThis, 'document')
  const events = new EventTarget()
  const localStorage = new MemoryStorage()
  const sessionStorage = new MemoryStorage()
  const historyStates: unknown[] = []
  const replacements: string[] = []
  const browserWindow = {
    crypto: {
      randomUUID: () => 'test-history-epoch',
    },
    get localStorage() {
      if (options.storageThrows) throw new Error('storage disabled')
      return localStorage
    },
    get sessionStorage() {
      if (options.storageThrows) throw new Error('storage disabled')
      return sessionStorage
    },
    history: {
      replaceState: (state: unknown) => historyStates.push(state),
    },
    location: {
      href: 'https://mcweb.example/app/account',
      origin: 'https://mcweb.example',
      replace: (href: string) => replacements.push(href),
    },
    addEventListener: events.addEventListener.bind(events),
    removeEventListener: events.removeEventListener.bind(events),
  }

  Object.defineProperty(globalThis, 'window', {
    configurable: true,
    value: browserWindow,
  })
  Object.defineProperty(globalThis, 'document', {
    configurable: true,
    value: { title: 'Private account' },
  })

  return {
    localStorage,
    sessionStorage,
    historyStates,
    replacements,
    dispatchStorage(key: string) {
      const event = new Event('storage') as Event & { key: string }
      Object.defineProperty(event, 'key', { value: key })
      events.dispatchEvent(event)
    },
    dispatchPageShow() {
      events.dispatchEvent(new Event('pageshow'))
    },
    restore() {
      if (previousWindow) Object.defineProperty(globalThis, 'window', previousWindow)
      else Reflect.deleteProperty(globalThis, 'window')
      if (previousDocument) Object.defineProperty(globalThis, 'document', previousDocument)
      else Reflect.deleteProperty(globalThis, 'document')
    },
  }
}

test('invalidating an authenticated document clears encryption and leaves a tombstone', () => {
  const browser = installBrowserHarness()
  try {
    browser.sessionStorage.setItem('historyKey', 'secret-key')
    browser.sessionStorage.setItem('historyIv', 'secret-iv')
    const remove = installAuthenticatedHistoryBoundary('/signed-out')

    invalidateAuthenticatedHistory()

    assert.equal(browser.sessionStorage.getItem('historyKey'), null)
    assert.equal(browser.sessionStorage.getItem('historyIv'), null)
    assert.equal(browser.sessionStorage.getItem('mcweb:authenticated-history-armed'), null)
    assert.equal(
      browser.localStorage.getItem('mcweb:authenticated-history-epoch'),
      'test-history-epoch',
    )
    assert.deepEqual(browser.historyStates.at(-1), { mcwebSessionInvalidated: true })
    remove()
  } finally {
    browser.restore()
  }
})

test('a guest document consumes the marker left by a previous authenticated document', () => {
  const browser = installBrowserHarness()
  try {
    const remove = installAuthenticatedHistoryBoundary('/signed-out')
    remove()

    assert.equal(invalidatePreviouslyAuthenticatedHistory(), true)
    assert.equal(invalidatePreviouslyAuthenticatedHistory(), false)
    assert.deepEqual(browser.historyStates.at(-1), { mcwebSessionInvalidated: true })
  } finally {
    browser.restore()
  }
})

test('another tab epoch and a restored page both leave an invalid authenticated document', () => {
  const browser = installBrowserHarness()
  try {
    const remove = installAuthenticatedHistoryBoundary('/signed-out')
    browser.localStorage.setItem('mcweb:authenticated-history-epoch', 'other-tab-epoch')
    browser.dispatchStorage('mcweb:authenticated-history-epoch')
    browser.dispatchPageShow()

    assert.deepEqual(browser.replacements, ['https://mcweb.example/signed-out'])
    assert.deepEqual(browser.historyStates.at(-1), { mcwebSessionInvalidated: true })
    remove()
  } finally {
    browser.restore()
  }
})

test('disabled browser storage still allows the current history entry to be scrubbed', () => {
  const browser = installBrowserHarness({ storageThrows: true })
  try {
    assert.doesNotThrow(() => invalidateAuthenticatedHistory())
    assert.deepEqual(browser.historyStates.at(-1), { mcwebSessionInvalidated: true })
  } finally {
    browser.restore()
  }
})
