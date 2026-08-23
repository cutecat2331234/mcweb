import { csrfHeaders } from '@/lib/csrf'
import {
  frontendApplicationRequestHeaders,
  frontendRouteSourceAllowed,
  resolveFrontendRoute,
} from '@/lib/frontendApplications'
import { localeRequestHeaders } from '@/lib/localePreference'
import {
  recoverFrontendSafeLocation,
  SAFE_FRONTEND_LOCATION_HEADER,
} from '@/lib/applicationNavigation'

export type SharedActionMethod = 'POST' | 'PUT' | 'PATCH' | 'DELETE'

type SharedActionOptions = {
  method: SharedActionMethod
  data?: Record<string, unknown> | FormData
  signal?: AbortSignal
}

export class SharedActionError extends Error {
  readonly status: number
  readonly recoveryStarted: boolean

  constructor(message: string, status: number, recoveryStarted = false) {
    super(message)
    this.name = 'SharedActionError'
    this.status = status
    this.recoveryStarted = recoveryStarted
  }
}

function sharedActionUrl(path: string): URL {
  const url = new URL(path, window.location.href)
  if (url.origin !== window.location.origin) {
    throw new Error(`Shared action must be same-origin: ${path}`)
  }
  return url
}

export async function performSharedAction(
  applicationId: string,
  path: string,
  { method, data, signal }: SharedActionOptions,
): Promise<Response> {
  const url = sharedActionUrl(path)
  const match = resolveFrontendRoute(url.pathname, method)
  if (!match || match.rule.kind !== 'shared_action') {
    throw new Error(`Unregistered shared action: ${method} ${url.pathname}`)
  }
  if (!frontendRouteSourceAllowed(match, applicationId)) {
    throw new Error(`Frontend application ${applicationId} cannot call ${method} ${url.pathname}`)
  }

  const body = data instanceof FormData ? data : JSON.stringify(data ?? {})
  const headers: Record<string, string> = {
    Accept: 'application/json',
    ...csrfHeaders(),
    ...localeRequestHeaders(),
    ...frontendApplicationRequestHeaders(applicationId),
  }
  if (!(data instanceof FormData)) headers['Content-Type'] = 'application/json'

  const response = await fetch(url, {
    method,
    headers,
    body,
    credentials: 'same-origin',
    redirect: 'follow',
    signal,
  })
  if (!response.ok) {
    const recoveryStarted = response.status === 409
      && recoverFrontendSafeLocation(response.headers.get(SAFE_FRONTEND_LOCATION_HEADER))
    throw new SharedActionError(
      `Shared action failed (${response.status}): ${method} ${url.pathname}`,
      response.status,
      recoveryStarted,
    )
  }
  return response
}
