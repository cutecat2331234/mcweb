import { computed, onScopeDispose, reactive, watch } from 'vue'
import { csrfHeaders } from './csrf.ts'
import {
  createCommunityRelationshipMutation,
  reconcileCommunityRelationshipMutation,
  resetCommunityRelationshipMutation,
  submitCommunityRelationshipMutation,
  type CommunityRelationshipIntent,
  type CommunityRelationshipMutationState,
  type CommunityRelationshipResponse,
  type CommunityRelationshipSnapshot,
} from './communityRelationshipMutation.ts'

async function requestRelationship(url: string, intent: Readonly<CommunityRelationshipIntent>): Promise<CommunityRelationshipResponse> {
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), 15_000)
  try {
    const response = await fetch(url, {
      method: intent.method.toUpperCase(),
      headers: { Accept: 'application/json', 'Content-Type': 'application/json', ...csrfHeaders() },
      credentials: 'same-origin',
      cache: 'no-store',
      redirect: 'error',
      signal: controller.signal,
      body: JSON.stringify({ expected_revision: intent.expectedRevision }),
    })
    const body = await response.json()
    return { ok: response.ok, status: response.status, data: body.data }
  } finally {
    clearTimeout(timeout)
  }
}

export function useCommunityRelationship(
  getUrl: () => string | null | undefined,
  getSnapshot: () => CommunityRelationshipSnapshot | undefined,
  onConfirmed?: () => void,
) {
  const state = reactive(createCommunityRelationshipMutation(getSnapshot()))
  watch([getUrl, getSnapshot], ([url, snapshot], [previousUrl]) => {
    if (url !== previousUrl) resetCommunityRelationshipMutation(state, snapshot)
    else reconcileCommunityRelationshipMutation(state, snapshot)
  }, { flush: 'sync' })
  onScopeDispose(() => resetCommunityRelationshipMutation(state))

  async function submit() {
    const url = getUrl()
    if (!url) return
    const outcome = await submitCommunityRelationshipMutation(state, intent => requestRelationship(url, intent))
    if (outcome === 'confirmed') onConfirmed?.()
  }

  return { state, submit }
}

interface RelationshipListUser {
  username: string
  relationship: CommunityRelationshipSnapshot
}

export function useCommunityRelationshipList<T extends RelationshipListUser>(getUsers: () => T[], onConfirmed?: () => void) {
  // Usernames are external keys. A Map avoids both Object prototype collisions
  // and Vue proxy-reserved properties such as "__v_isReactive" and "__v_raw".
  const states = reactive(new Map<string, CommunityRelationshipMutationState>())
  watch(getUsers, users => {
    for (const user of users) {
      let state = states.get(user.username)
      if (!state) {
        state = createCommunityRelationshipMutation(user.relationship)
        states.set(user.username, state)
      }
      reconcileCommunityRelationshipMutation(state, user.relationship)
    }
  }, { immediate: true })
  onScopeDispose(() => {
    for (const state of states.values()) resetCommunityRelationshipMutation(state)
  })

  const visibleUsers = computed(() => getUsers().filter(user => states.get(user.username)?.active !== false))

  async function remove(user: T, url: string) {
    const state = states.get(user.username)
    if (!state) return
    const outcome = await submitCommunityRelationshipMutation(state, intent => requestRelationship(url, intent), false)
    if (outcome === 'confirmed') onConfirmed?.()
  }

  return { states, visibleUsers, remove }
}
