import assert from 'node:assert/strict'
import test from 'node:test'

import {
  CONTROLLED_REQUEST_CANCELLATION_BINDING,
  CONTROLLED_REQUEST_ID_HEADER,
  createControlledRequestCancellation,
  type ControlledRequestCancellationEvent,
} from '../../app/javascript/lib/controlledRequestCancellation.ts'

type DiagnosticGlobal = typeof globalThis & {
  [CONTROLLED_REQUEST_CANCELLATION_BINDING]?: (
    event: ControlledRequestCancellationEvent,
  ) => void | Promise<unknown>
}

test('controlled request cancellation correlates the request and reports before aborting', () => {
  const diagnosticGlobal = globalThis as DiagnosticGlobal
  const previous = diagnosticGlobal[CONTROLLED_REQUEST_CANCELLATION_BINDING]
  const events: ControlledRequestCancellationEvent[] = []
  let request = createControlledRequestCancellation()

  diagnosticGlobal[CONTROLLED_REQUEST_CANCELLATION_BINDING] = (event) => {
    assert.equal(request.controller.signal.aborted, false)
    events.push(event)
  }
  try {
    request = createControlledRequestCancellation()
    assert.equal(request.headers[CONTROLLED_REQUEST_ID_HEADER], request.requestId)
    assert.match(request.requestId, /^v1\./)
    assert.equal(request.cancel('component_unmounted'), true)
    assert.equal(request.controller.signal.aborted, true)
    assert.equal(request.controller.signal.reason, 'component_unmounted')
    assert.deepEqual(events, [{ requestId: request.requestId, reason: 'component_unmounted' }])
    assert.equal(request.cancel('deadline_exceeded'), false)
    assert.equal(events.length, 1)
  } finally {
    if (previous) diagnosticGlobal[CONTROLLED_REQUEST_CANCELLATION_BINDING] = previous
    else delete diagnosticGlobal[CONTROLLED_REQUEST_CANCELLATION_BINDING]
  }
})

test('diagnostic reporting failures cannot prevent operational cancellation', () => {
  const diagnosticGlobal = globalThis as DiagnosticGlobal
  const previous = diagnosticGlobal[CONTROLLED_REQUEST_CANCELLATION_BINDING]
  diagnosticGlobal[CONTROLLED_REQUEST_CANCELLATION_BINDING] = () => {
    throw new Error('diagnostic transport unavailable')
  }
  try {
    const request = createControlledRequestCancellation()
    assert.equal(request.cancel('deadline_exceeded'), true)
    assert.equal(request.controller.signal.aborted, true)
    assert.equal(request.controller.signal.reason, 'deadline_exceeded')
  } finally {
    if (previous) diagnosticGlobal[CONTROLLED_REQUEST_CANCELLATION_BINDING] = previous
    else delete diagnosticGlobal[CONTROLLED_REQUEST_CANCELLATION_BINDING]
  }
})

test('an asynchronous diagnostic acknowledgement never delays request cancellation', async () => {
  const diagnosticGlobal = globalThis as DiagnosticGlobal
  const previous = diagnosticGlobal[CONTROLLED_REQUEST_CANCELLATION_BINDING]
  let acknowledge!: () => void
  let request = createControlledRequestCancellation()
  diagnosticGlobal[CONTROLLED_REQUEST_CANCELLATION_BINDING] = () => {
    assert.equal(request.controller.signal.aborted, false)
    return new Promise<void>((resolve) => {
      acknowledge = resolve
    })
  }
  try {
    request = createControlledRequestCancellation()
    assert.equal(request.cancel('component_unmounted'), true)
    assert.equal(request.controller.signal.aborted, true)
    assert.equal(request.controller.signal.reason, 'component_unmounted')
    acknowledge()
    await new Promise<void>((resolve) => setImmediate(resolve))
    assert.equal(request.controller.signal.aborted, true)
  } finally {
    if (previous) diagnosticGlobal[CONTROLLED_REQUEST_CANCELLATION_BINDING] = previous
    else delete diagnosticGlobal[CONTROLLED_REQUEST_CANCELLATION_BINDING]
  }
})

test('an unresponsive diagnostic reporter cannot delay cancellation', () => {
  const diagnosticGlobal = globalThis as DiagnosticGlobal
  const previous = diagnosticGlobal[CONTROLLED_REQUEST_CANCELLATION_BINDING]
  diagnosticGlobal[CONTROLLED_REQUEST_CANCELLATION_BINDING] = () => new Promise(() => undefined)
  try {
    const request = createControlledRequestCancellation()
    assert.equal(request.cancel('deadline_exceeded'), true)
    assert.equal(request.controller.signal.aborted, true)
    assert.equal(request.controller.signal.reason, 'deadline_exceeded')
  } finally {
    if (previous) diagnosticGlobal[CONTROLLED_REQUEST_CANCELLATION_BINDING] = previous
    else delete diagnosticGlobal[CONTROLLED_REQUEST_CANCELLATION_BINDING]
  }
})
