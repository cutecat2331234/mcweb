export interface CommunityRelationshipSnapshot {
  active: boolean
  // Decimal strings preserve every PostgreSQL bigint revision in JavaScript.
  revision: string
}

export interface CommunityRelationshipIntent {
  desiredState: boolean
  expectedRevision: string
  method: 'put' | 'delete'
}

export interface CommunityRelationshipMutationState extends CommunityRelationshipSnapshot {
  processing: boolean
  pending: Readonly<CommunityRelationshipIntent> | null
  error: 'retry' | 'conflict' | 'failed' | null
  generation: number
}

export interface CommunityRelationshipResponse {
  ok: boolean
  status: number
  data?: unknown
}

export function isCommunityRelationshipSnapshot(value: unknown): value is CommunityRelationshipSnapshot {
  if (!value || typeof value !== 'object') return false
  const snapshot = value as Partial<CommunityRelationshipSnapshot>
  return typeof snapshot.active === 'boolean'
    && typeof snapshot.revision === 'string'
    && /^(0|[1-9][0-9]{0,18})$/.test(snapshot.revision)
}

export function createCommunityRelationshipMutation(
  snapshot?: CommunityRelationshipSnapshot,
): CommunityRelationshipMutationState {
  return { active: snapshot?.active ?? false, revision: snapshot?.revision ?? '', processing: false, pending: null, error: null, generation: 0 }
}

export function resetCommunityRelationshipMutation(
  state: CommunityRelationshipMutationState,
  snapshot?: CommunityRelationshipSnapshot,
): void {
  Object.assign(state, createCommunityRelationshipMutation(snapshot), { generation: state.generation + 1 })
}

export function reconcileCommunityRelationshipMutation(
  state: CommunityRelationshipMutationState,
  snapshot: unknown,
): void {
  if (!isCommunityRelationshipSnapshot(snapshot)) return
  // A slow response/page reload must not overwrite a newer confirmed snapshot.
  if (snapshot.revision.length < state.revision.length) return
  if (snapshot.revision.length === state.revision.length && snapshot.revision < state.revision) return
  state.active = snapshot.active
  state.revision = snapshot.revision
}

export async function submitCommunityRelationshipMutation(
  state: CommunityRelationshipMutationState,
  request: (intent: Readonly<CommunityRelationshipIntent>) => Promise<CommunityRelationshipResponse>,
  desiredState: boolean = !state.active,
): Promise<'busy' | 'confirmed' | 'rejected' | 'uncertain'> {
  if (state.processing) return 'busy'
  if (!isCommunityRelationshipSnapshot({
    active: state.active,
    revision: state.revision,
  })) {
    state.error = 'failed'
    return 'rejected'
  }

  // Unknown outcomes retain exactly the same desired state AND precondition.
  // In particular, never refresh/rebase a timed-out DELETE onto a newer block.
  state.pending ??= Object.freeze({
    desiredState,
    expectedRevision: state.revision,
    method: desiredState ? 'put' : 'delete',
  })
  state.processing = true
  state.error = null
  const generation = state.generation
  try {
    const response = await request(state.pending)
    if (state.generation !== generation) return 'busy'
    if ((response.ok || response.status === 409 || response.status === 428) && isCommunityRelationshipSnapshot(response.data)) {
      reconcileCommunityRelationshipMutation(state, response.data)
      state.pending = null
      state.error = response.ok ? null : 'conflict'
      return 'confirmed'
    }
    if (response.status >= 400 && response.status < 500 && response.status !== 409) {
      state.pending = null
      state.error = 'failed'
      return 'rejected'
    }
    // A server error or malformed success can occur after commit, just like a
    // timeout. Do not infer whether the mutation was applied.
    state.error = 'retry'
    return 'uncertain'
  } catch {
    if (state.generation !== generation) return 'busy'
    state.error = 'retry'
    return 'uncertain'
  } finally {
    if (state.generation === generation) state.processing = false
  }
}
