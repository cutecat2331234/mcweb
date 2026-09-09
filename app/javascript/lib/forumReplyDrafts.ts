import {
  browserLocalStorageDraftPersistence,
  defineFrontendDraftAdapter,
} from './frontendDrafts.ts'

const persistence = browserLocalStorageDraftPersistence<string>()
type DraftInvalidation = 'suspend' | 'clear'
const invalidationListeners = new Set<(reason: DraftInvalidation) => void>()
const LEGACY_REPLY_DRAFT_PREFIX = 'forum-reply-draft-'

export const forumReplyDraftAdapter = defineFrontendDraftAdapter<string>({
  contract: {
    capability: 'forum_reply_drafts',
    keyNamespace: 'forum_reply_drafts',
    version: 1,
    userScoped: true,
    resourceScoped: true,
    offlineRecovery: true,
    clearOnSubmit: true,
  },
  persistence,
})

export function discardLegacyForumReplyDrafts(): void {
  try {
    const storage = window.localStorage
    for (let index = storage.length - 1; index >= 0; index -= 1) {
      const key = storage.key(index)
      // Ownerless legacy drafts cannot be safely assigned to the current user.
      if (key?.startsWith(LEGACY_REPLY_DRAFT_PREFIX)) void persistence.remove(key)
    }
  } catch {
    // Storage may be unavailable; legacy drafts are never read or migrated.
  }
}

export function onForumReplyDraftsInvalidated(
  listener: (reason: DraftInvalidation) => void,
): VoidFunction {
  invalidationListeners.add(listener)
  return () => { invalidationListeners.delete(listener) }
}

function invalidateDraftConsumers(reason: DraftInvalidation): void {
  for (const listener of invalidationListeners) {
    try {
      listener(reason)
    } catch {
      // One mounted consumer must not prevent the storage boundary from clearing.
    }
  }
}

export function suspendForumReplyDrafts(): void {
  invalidateDraftConsumers('suspend')
}

export function clearForumReplyDrafts(): void {
  invalidateDraftConsumers('clear')
  persistence.clearNamespace(forumReplyDraftAdapter.contract.keyNamespace)
  discardLegacyForumReplyDrafts()
}
