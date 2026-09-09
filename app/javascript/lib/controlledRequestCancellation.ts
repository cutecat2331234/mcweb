import { createIdempotencyKey } from './idempotency.ts'

export const CONTROLLED_REQUEST_ID_HEADER = 'X-McWeb-Controlled-Request-Id'
export const CONTROLLED_REQUEST_CANCELLATION_BINDING =
  '__mcwebReportControlledRequestCancellation'

export const CONTROLLED_REQUEST_CANCELLATION_REASONS = [
  'browser_offline',
  'component_unmounted',
  'deadline_exceeded',
  'request_superseded',
  'state_changed',
  'user_cancelled',
] as const

export type ControlledRequestCancellationReason =
  (typeof CONTROLLED_REQUEST_CANCELLATION_REASONS)[number]

export type ControlledRequestCancellationEvent = {
  requestId: string
  reason: ControlledRequestCancellationReason
}

type CancellationReporter = (
  event: ControlledRequestCancellationEvent,
) => void | Promise<unknown>

type DiagnosticGlobal = typeof globalThis & {
  [CONTROLLED_REQUEST_CANCELLATION_BINDING]?: CancellationReporter
}

/**
 * Creates a request-scoped AbortController that can prove application-owned
 * cancellation to an attached browser diagnostic collector. The request ID
 * alone never excuses a failed request: the collector also requires this
 * instance to report the exact cancellation before calling AbortController.
 */
export function createControlledRequestCancellation() {
  const requestId = `v1.${createIdempotencyKey()}`
  const controller = new AbortController()
  let cancellationStarted = false

  function cancel(reason: ControlledRequestCancellationReason): boolean {
    if (cancellationStarted || controller.signal.aborted) return false
    cancellationStarted = true

    const reporter = (globalThis as DiagnosticGlobal)[
      CONTROLLED_REQUEST_CANCELLATION_BINDING
    ]
    try {
      const result = reporter?.({ requestId, reason })
      if (result && typeof result.then === 'function') {
        // Reporting is diagnostic-only. Playwright acknowledges the binding
        // asynchronously, but that acknowledgement must never extend the
        // operational lifetime of the request being cancelled.
        void result.catch(() => undefined)
      }
    } catch {
      // Diagnostics must not become operational state.
    }
    controller.abort(reason)
    return true
  }

  return {
    requestId,
    controller,
    headers: Object.freeze({
      [CONTROLLED_REQUEST_ID_HEADER]: requestId,
    }),
    cancel,
  }
}

export type ControlledRequestCancellation =
  ReturnType<typeof createControlledRequestCancellation>
