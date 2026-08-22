export type CommunityRelationshipMethod = 'put' | 'delete'

type MutableBoolean = { value: boolean }

export function beginCommunityRelationshipMutation(
  processing: MutableBoolean,
  currentState: boolean,
): { desiredState: boolean; method: CommunityRelationshipMethod } | null {
  if (processing.value) return null

  processing.value = true
  const desiredState = !currentState
  return { desiredState, method: desiredState ? 'put' : 'delete' }
}

export function finishCommunityRelationshipMutation(processing: MutableBoolean): void {
  processing.value = false
}
