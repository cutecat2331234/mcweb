import {
  onBeforeUnmount,
  toValue,
  watch,
  type MaybeRefOrGetter,
} from 'vue'

type UnsavedFormRecord = {
  dirty: boolean
  message: string
}

export type UnsavedFormRegistration = {
  isDirty: () => boolean
  setDirty: (dirty?: boolean) => void
  saved: () => void
  discard: () => void
  release: () => void
}

const records = new Map<symbol, UnsavedFormRecord>()
const automaticForms = new Map<HTMLFormElement, UnsavedFormRegistration>()
const submittedFormsByVisit = new Map<string, {
  registration: UnsavedFormRegistration
  wasDirty: boolean
}>()
let candidateSubmittedForm: {
  form: HTMLFormElement
  registration: UnsavedFormRegistration
  wasDirty: boolean
} | null = null
let documentNavigationApproval: { destination: string | null; expiresAt: number } | null = null
let guardConsumers = 0
let removeInstalledGuards: VoidFunction | null = null

export function hasUnsavedForms(): boolean {
  for (const [form, registration] of automaticForms) {
    if (form.isConnected) continue
    registration.release()
    automaticForms.delete(form)
  }
  return [...records.values()].some((record) => record.dirty)
}

function defaultMessage(): string {
  return typeof document !== 'undefined' && document.documentElement.lang
    .toLowerCase()
    .startsWith('zh')
    ? '你有尚未保存的更改。确定离开此页面吗？'
    : 'You have unsaved changes. Leave this page?'
}

function activeMessage(): string {
  return [...records.values()].find((record) => record.dirty)?.message ?? defaultMessage()
}

export function registerUnsavedForm(message = defaultMessage()): UnsavedFormRegistration {
  const token = Symbol('unsaved-form')
  records.set(token, { dirty: false, message })

  const setDirty = (dirty = true) => {
    const record = records.get(token)
    if (record) record.dirty = dirty
  }
  const release = () => records.delete(token)

  return {
    isDirty: () => records.get(token)?.dirty === true,
    setDirty,
    saved: () => setDirty(false),
    discard: () => setDirty(false),
    release,
  }
}

export function useUnsavedForm(
  dirty: MaybeRefOrGetter<boolean>,
  message = defaultMessage(),
): UnsavedFormRegistration {
  const registration = registerUnsavedForm(message)
  const stop = watch(
    () => Boolean(toValue(dirty)),
    (value) => registration.setDirty(value),
    { immediate: true },
  )

  onBeforeUnmount(() => {
    stop()
    registration.release()
  })
  return registration
}

export function confirmUnsavedNavigation(): boolean {
  if (!hasUnsavedForms()) return true
  return window.confirm(activeMessage())
}

export function claimSubmittedForm(visitId: string): void {
  if (!candidateSubmittedForm) return
  submittedFormsByVisit.set(visitId, {
    registration: candidateSubmittedForm.registration,
    wasDirty: candidateSubmittedForm.wasDirty,
  })
  candidateSubmittedForm = null
}

export function completeSubmittedForm(visitId?: string): void {
  if (!visitId) return
  submittedFormsByVisit.get(visitId)?.registration.saved()
  submittedFormsByVisit.delete(visitId)
}

export function releaseSubmittedForm(visitId: string): void {
  const submission = submittedFormsByVisit.get(visitId)
  if (submission?.wasDirty) submission.registration.setDirty()
  submittedFormsByVisit.delete(visitId)
}

export function approveNextDocumentNavigation(destination?: string): void {
  documentNavigationApproval = {
    destination: destination ?? null,
    expiresAt: Date.now() + 1500,
  }
}

export function cancelDocumentNavigationApproval(): void {
  documentNavigationApproval = null
}

function documentNavigationIsApproved(): boolean {
  if (!documentNavigationApproval) return false
  if (Date.now() > documentNavigationApproval.expiresAt) {
    documentNavigationApproval = null
    return false
  }
  return true
}

type BrowserNavigateEvent = Event & {
  navigationType?: string
  canIntercept?: boolean
}

type BrowserNavigation = {
  addEventListener: (type: 'navigate', listener: EventListener) => void
  removeEventListener: (type: 'navigate', listener: EventListener) => void
}

export function installUnsavedFormGuards(): VoidFunction {
  if (typeof window === 'undefined') return () => {}
  guardConsumers += 1
  if (removeInstalledGuards) {
    let released = false
    return () => {
      if (released) return
      released = true
      guardConsumers -= 1
      if (guardConsumers === 0) removeInstalledGuards?.()
    }
  }

  const onBeforeUnload = (event: BeforeUnloadEvent) => {
    if (documentNavigationIsApproved()) {
      documentNavigationApproval = null
      return
    }
    if (!hasUnsavedForms()) return
    event.preventDefault()
    event.returnValue = ''
  }

  const onInput = (event: Event) => {
    const target = event.target
    if (!(target instanceof Element)) return
    const form = target.closest<HTMLFormElement>('form')
    if (!form || !form.hasAttribute('data-mcweb-unsaved')) return
    let registration = automaticForms.get(form)
    if (!registration) {
      registration = registerUnsavedForm()
      automaticForms.set(form, registration)
    }
    registration.setDirty()
  }

  const onReset = (event: Event) => {
    if (!(event.target instanceof HTMLFormElement)) return
    const form = event.target
    window.setTimeout(() => {
      if (!event.defaultPrevented) automaticForms.get(form)?.saved()
    }, 0)
  }

  const onSubmit = (event: Event) => {
    if (!(event.target instanceof HTMLFormElement)) return
    const form = event.target
    const registration = automaticForms.get(form)
    if (!registration) return
    const wasDirty = registration.isDirty()
    registration.saved()
    candidateSubmittedForm = { form, registration, wasDirty }
    window.setTimeout(() => {
      if (candidateSubmittedForm?.form !== form) return
      if (event.defaultPrevented && wasDirty) registration.setDirty()
      candidateSubmittedForm = null
    }, 0)
  }

  const browserNavigation = (window as Window & { navigation?: BrowserNavigation }).navigation
  const onNavigate: EventListener = (rawEvent) => {
    const event = rawEvent as BrowserNavigateEvent
    if (event.navigationType !== 'traverse' || !event.canIntercept || !hasUnsavedForms()) return
    if (!confirmUnsavedNavigation()) event.preventDefault()
  }

  const history = window.history
  const originalPushState = history.pushState
  const originalReplaceState = history.replaceState
  const historyEntryStateKey = '__mcwebUnsavedHistoryEntry'
  const originalHistoryStateKey = '__mcwebOriginalHistoryState'
  const historySessionId = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`
  let nextHistoryEntryId = 0
  type HistoryEntry = { sessionId: string; entryId: string; index: number }
  const createHistoryEntry = (index: number): HistoryEntry => ({
    sessionId: historySessionId,
    entryId: `${historySessionId}:${nextHistoryEntryId += 1}`,
    index,
  })
  const stateWithHistoryEntry = (data: unknown, entry: HistoryEntry) => {
    const state = data !== null && typeof data === 'object' && !Array.isArray(data)
      ? { ...(data as Record<string, unknown>) }
      : { [originalHistoryStateKey]: data }
    return { ...state, [historyEntryStateKey]: entry }
  }
  const historyEntryFromState = (data: unknown): HistoryEntry | null => {
    if (data === null || typeof data !== 'object') return null
    const entry = (data as Record<string, unknown>)[historyEntryStateKey]
    if (entry === null || typeof entry !== 'object') return null
    const candidate = entry as Partial<HistoryEntry>
    return candidate.sessionId === historySessionId
      && typeof candidate.entryId === 'string'
      && typeof candidate.index === 'number'
      && Number.isInteger(candidate.index)
      ? candidate as HistoryEntry
      : null
  }

  let currentHistoryEntry = createHistoryEntry(0)
  let replayTargetEntryId: string | null = null
  Reflect.apply(originalReplaceState, history, [
    stateWithHistoryEntry(history.state, currentHistoryEntry),
    '',
    window.location.href,
  ])

  const wrappedPushState: History['pushState'] = function pushState(data, unused, url) {
    const entry = createHistoryEntry(currentHistoryEntry.index + 1)
    Reflect.apply(originalPushState, history, [stateWithHistoryEntry(data, entry), unused, url])
    currentHistoryEntry = entry
  }
  const wrappedReplaceState: History['replaceState'] = function replaceState(data, unused, url) {
    Reflect.apply(originalReplaceState, history, [
      stateWithHistoryEntry(data, currentHistoryEntry),
      unused,
      url,
    ])
  }
  history.pushState = wrappedPushState
  history.replaceState = wrappedReplaceState

  const onPopState = (event: PopStateEvent) => {
    const destinationEntry = historyEntryFromState(event.state)
    if (!destinationEntry) return
    if (browserNavigation) {
      currentHistoryEntry = destinationEntry
      return
    }
    if (replayTargetEntryId === destinationEntry.entryId) {
      replayTargetEntryId = null
      currentHistoryEntry = destinationEntry
      event.stopImmediatePropagation()
      return
    }
    if (hasUnsavedForms() && !confirmUnsavedNavigation()) {
      event.stopImmediatePropagation()
      replayTargetEntryId = currentHistoryEntry.entryId
      history.go(currentHistoryEntry.index - destinationEntry.index)
      window.setTimeout(() => {
        replayTargetEntryId = null
      }, 1000)
      return
    }
    currentHistoryEntry = destinationEntry
  }

  window.addEventListener('beforeunload', onBeforeUnload)
  document.addEventListener('input', onInput, true)
  document.addEventListener('change', onInput, true)
  document.addEventListener('reset', onReset, true)
  document.addEventListener('submit', onSubmit, true)
  browserNavigation?.addEventListener('navigate', onNavigate)
  window.addEventListener('popstate', onPopState, true)
  removeInstalledGuards = () => {
    window.removeEventListener('beforeunload', onBeforeUnload)
    document.removeEventListener('input', onInput, true)
    document.removeEventListener('change', onInput, true)
    document.removeEventListener('reset', onReset, true)
    document.removeEventListener('submit', onSubmit, true)
    browserNavigation?.removeEventListener('navigate', onNavigate)
    window.removeEventListener('popstate', onPopState, true)
    if (history.pushState === wrappedPushState) history.pushState = originalPushState
    if (history.replaceState === wrappedReplaceState) history.replaceState = originalReplaceState
    for (const registration of automaticForms.values()) registration.release()
    automaticForms.clear()
    submittedFormsByVisit.clear()
    candidateSubmittedForm = null
    documentNavigationApproval = null
    removeInstalledGuards = null
  }

  let released = false
  return () => {
    if (released) return
    released = true
    guardConsumers -= 1
    if (guardConsumers === 0) removeInstalledGuards?.()
  }
}
