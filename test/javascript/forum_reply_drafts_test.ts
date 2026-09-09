import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

import {
  browserLocalStorageDraftPersistence,
  canonicalFrontendDraftKeyStrategy,
  defineFrontendDraftAdapter,
} from '../../app/javascript/lib/frontendDrafts.ts'
import {
  clearForumReplyDrafts,
  discardLegacyForumReplyDrafts,
  forumReplyDraftAdapter,
  onForumReplyDraftsInvalidated,
  suspendForumReplyDrafts,
} from '../../app/javascript/lib/forumReplyDrafts.ts'

class MemoryStorage {
  private readonly values = new Map<string, string>()

  get length(): number { return this.values.size }
  key(index: number): string | null { return Array.from(this.values.keys())[index] ?? null }
  getItem(key: string): string | null { return this.values.get(key) ?? null }
  setItem(key: string, value: string): void { this.values.set(key, value) }
  removeItem(key: string): void { this.values.delete(key) }
}

function installBrowserStorage() {
  const previousWindow = Object.getOwnPropertyDescriptor(globalThis, 'window')
  const storage = new MemoryStorage()
  let blocked = false
  Object.defineProperty(globalThis, 'window', {
    configurable: true,
    value: {
      get localStorage() {
        if (blocked) throw new Error('storage disabled')
        return storage
      },
    },
  })
  return {
    storage,
    block: () => { blocked = true },
    restore: () => {
      if (previousWindow) Object.defineProperty(globalThis, 'window', previousWindow)
      else Reflect.deleteProperty(globalThis, 'window')
    },
  }
}

const userA = { userId: 'user-a', resourceId: 'topic-1' }
const userB = { userId: 'user-b', resourceId: 'topic-1' }

test('forum replies use the canonical versioned user and topic envelope', async () => {
  const browser = installBrowserStorage()
  try {
    const context = { userId: 'user/a', resourceId: 'topic/b' }
    await forumReplyDraftAdapter.persist(context, 'My private reply')
    const key = forumReplyDraftAdapter.storageKey(context)
    assert.equal(key, 'mcweb-draft/forum_reply_drafts/v1/user%2Fa/topic%2Fb')
    assert.deepEqual(canonicalFrontendDraftKeyStrategy.parse(key), {
      namespace: 'forum_reply_drafts', version: 1, userId: 'user/a', resourceId: 'topic/b',
    })
    const envelope = JSON.parse(browser.storage.getItem(key)!)
    assert.equal(envelope.namespace, 'forum_reply_drafts')
    assert.equal(envelope.version, 1)
    assert.equal(envelope.userId, 'user/a')
    assert.equal(envelope.resourceId, 'topic/b')
    assert.equal(envelope.payload, 'My private reply')
    assert.ok(Number.isFinite(Date.parse(envelope.savedAt)))
    assert.equal(await forumReplyDraftAdapter.restore(context), 'My private reply')
  } finally {
    clearForumReplyDrafts()
    browser.restore()
  }
})

test('switching accounts or topics cannot restore another identity draft', async () => {
  const browser = installBrowserStorage()
  try {
    await forumReplyDraftAdapter.persist(userA, 'A only')
    assert.equal(await forumReplyDraftAdapter.restore(userB), null)
    assert.equal(await forumReplyDraftAdapter.restore({ ...userA, resourceId: 'topic-2' }), null)
    await forumReplyDraftAdapter.persist(userB, 'B only')
    assert.equal(await forumReplyDraftAdapter.restore(userA), 'A only')
    assert.equal(await forumReplyDraftAdapter.restore(userB), 'B only')
    await assert.rejects(
      forumReplyDraftAdapter.restore({ userId: '', resourceId: 'topic-1' }),
      /userId must not be empty/,
    )
  } finally {
    clearForumReplyDrafts()
    browser.restore()
  }
})

test('foreign or obsolete envelopes under the current key are rejected and removed', async () => {
  const browser = installBrowserStorage()
  try {
    const key = forumReplyDraftAdapter.storageKey(userB)
    for (const mismatch of [
      { namespace: 'other_drafts' },
      { version: 2 },
      { userId: userA.userId },
      { resourceId: 'topic-2' },
    ]) {
      browser.storage.setItem(key, JSON.stringify({
        namespace: 'forum_reply_drafts', version: 1, ...userB,
        savedAt: new Date().toISOString(), payload: 'Foreign private reply', ...mismatch,
      }))
      assert.equal(await forumReplyDraftAdapter.restore(userB), null)
      assert.equal(browser.storage.getItem(key), null)
    }
    browser.storage.setItem(key, '{invalid-json')
    assert.equal(await forumReplyDraftAdapter.restore(userB), null)
    assert.equal(browser.storage.getItem(key), null)
  } finally {
    clearForumReplyDrafts()
    browser.restore()
  }
})

test('ownerless legacy drafts are discarded without recovery or unrelated storage removal', async () => {
  const browser = installBrowserStorage()
  try {
    browser.storage.setItem('forum-reply-draft-topic-1', 'Previous account private text')
    browser.storage.setItem('forum-reply-draft-topic-2', 'Another ownerless reply')
    browser.storage.setItem('mc-theme', 'dark')
    discardLegacyForumReplyDrafts()
    assert.equal(await forumReplyDraftAdapter.restore(userB), null)
    assert.equal(browser.storage.getItem('forum-reply-draft-topic-1'), null)
    assert.equal(browser.storage.getItem('forum-reply-draft-topic-2'), null)
    assert.equal(browser.storage.getItem('mc-theme'), 'dark')
  } finally {
    clearForumReplyDrafts()
    browser.restore()
  }
})

test('successful submission clears only the submitted user and topic draft', async () => {
  const browser = installBrowserStorage()
  try {
    const otherTopic = { ...userA, resourceId: 'topic-2' }
    await forumReplyDraftAdapter.persist(userA, 'Submitted reply')
    await forumReplyDraftAdapter.persist(userB, 'B still editing')
    await forumReplyDraftAdapter.persist(otherTopic, 'A other topic')
    await forumReplyDraftAdapter.submitted(userA)
    assert.equal(await forumReplyDraftAdapter.restore(userA), null)
    assert.equal(await forumReplyDraftAdapter.restore(userB), 'B still editing')
    assert.equal(await forumReplyDraftAdapter.restore(otherTopic), 'A other topic')
  } finally {
    clearForumReplyDrafts()
    browser.restore()
  }
})

test('sign-out cleanup stops mounted consumers and removes every stored reply version only', async () => {
  const browser = installBrowserStorage()
  let cleanupCalls = 0
  let cleanupSawDraft = false
  const reasons: string[] = []
  const removeCleanup = onForumReplyDraftsInvalidated((reason) => {
    cleanupCalls += 1
    reasons.push(reason)
    cleanupSawDraft = browser.storage.getItem(forumReplyDraftAdapter.storageKey(userA)) !== null
  })
  try {
    await forumReplyDraftAdapter.persist(userA, 'A local draft')
    await forumReplyDraftAdapter.persist(userB, 'B local draft')
    const obsoleteKey = canonicalFrontendDraftKeyStrategy.build(userA, {
      ...forumReplyDraftAdapter.contract, version: 2,
    })
    const unrelatedKey = canonicalFrontendDraftKeyStrategy.build(userA, {
      ...forumReplyDraftAdapter.contract, keyNamespace: 'other_drafts',
    })
    browser.storage.setItem(obsoleteKey, 'Obsolete reply format')
    browser.storage.setItem(unrelatedKey, 'Unrelated draft')
    browser.storage.setItem('forum-reply-draft-topic-1', 'Ownerless draft')
    browser.storage.setItem('mc-theme', 'dark')
    clearForumReplyDrafts()
    assert.equal(cleanupCalls, 1)
    assert.equal(cleanupSawDraft, true)
    assert.deepEqual(reasons, ['clear'])
    assert.equal(await forumReplyDraftAdapter.restore(userA), null)
    assert.equal(await forumReplyDraftAdapter.restore(userB), null)
    assert.equal(browser.storage.getItem(obsoleteKey), null)
    assert.equal(browser.storage.getItem('forum-reply-draft-topic-1'), null)
    assert.equal(browser.storage.getItem(unrelatedKey), 'Unrelated draft')
    assert.equal(browser.storage.getItem('mc-theme'), 'dark')
    removeCleanup()
    clearForumReplyDrafts()
    assert.equal(cleanupCalls, 1)
  } finally {
    removeCleanup()
    clearForumReplyDrafts()
    browser.restore()
  }
})

test('an unconfirmed sign-out suspends consumers without deleting recoverable drafts', async () => {
  const browser = installBrowserStorage()
  const reasons: string[] = []
  const removeCleanup = onForumReplyDraftsInvalidated((reason) => { reasons.push(reason) })
  try {
    await forumReplyDraftAdapter.persist(userA, 'Still recoverable if sign-out fails')
    suspendForumReplyDrafts()
    assert.deepEqual(reasons, ['suspend'])
    assert.equal(await forumReplyDraftAdapter.restore(userA), 'Still recoverable if sign-out fails')
    assert.equal(await forumReplyDraftAdapter.restore(userB), null)
  } finally {
    removeCleanup()
    clearForumReplyDrafts()
    browser.restore()
  }
})

test('disabled storage keeps fallback drafts isolated and sign-out clears the fallback', async () => {
  const browser = installBrowserStorage()
  try {
    browser.block()
    await forumReplyDraftAdapter.persist(userA, 'A memory-only draft')
    assert.equal(await forumReplyDraftAdapter.restore(userB), null)
    assert.equal(await forumReplyDraftAdapter.restore(userA), 'A memory-only draft')
    assert.doesNotThrow(() => clearForumReplyDrafts())
    assert.equal(await forumReplyDraftAdapter.restore(userA), null)
    assert.doesNotThrow(() => discardLegacyForumReplyDrafts())
  } finally {
    clearForumReplyDrafts()
    browser.restore()
  }
})

test('namespace cleanup preserves other namespaces and covers all fallback versions', async () => {
  const browser = installBrowserStorage()
  try {
    browser.block()
    const persistence = browserLocalStorageDraftPersistence<string>()
    const current = defineFrontendDraftAdapter({ contract: forumReplyDraftAdapter.contract, persistence })
    const obsolete = defineFrontendDraftAdapter({
      contract: { ...forumReplyDraftAdapter.contract, version: 2 }, persistence,
    })
    const unrelated = defineFrontendDraftAdapter({
      contract: { ...forumReplyDraftAdapter.contract, keyNamespace: 'other_drafts' }, persistence,
    })
    await current.persist(userA, 'Current reply')
    assert.equal(await obsolete.restore(userA), null)
    await obsolete.persist(userA, 'Obsolete reply')
    assert.equal(await current.restore(userA), 'Current reply')
    await unrelated.persist(userA, 'Other draft')
    persistence.clearNamespace(forumReplyDraftAdapter.contract.keyNamespace)
    assert.equal(await current.restore(userA), null)
    assert.equal(await obsolete.restore(userA), null)
    assert.equal(await unrelated.restore(userA), 'Other draft')
  } finally {
    browser.restore()
  }
})

const topicPage = readFileSync(resolve(process.cwd(), 'app/javascript/pages/Community/Topics/Show.vue'), 'utf8')
const draftHelper = readFileSync(resolve(process.cwd(), 'app/javascript/lib/forumReplyDrafts.ts'), 'utf8')

test('the topic page uses the shared adapter and never reads ownerless browser drafts', () => {
  assert.match(draftHelper, /defineFrontendDraftAdapter<string>/)
  assert.match(draftHelper, /browserLocalStorageDraftPersistence<string>/)
  assert.doesNotMatch(draftHelper, /recoverLegacy/)
  assert.doesNotMatch(topicPage, /localStorage|forum-reply-draft-/)
  assert.match(topicPage, /page\.props\.auth\.user\?\.id/)
  assert.match(topicPage, /return userId \? \{ userId, resourceId: props\.topic\.id \} : null/)
  assert.match(topicPage, /const hasServerDraft = props\.replyDraft != null \|\| attachments\.length > 0/)
  assert.match(topicPage, /const saved = hasServerDraft\s+\? \(props\.replyDraft \?\? ''\)\s+: await forumReplyDraftAdapter\.restore\(context\)/)
  assert.match(topicPage, /typeof saved === 'string' && !replyForm\.post\.body/)
  assert.match(topicPage, /props\.replyDraftAttachments \|\| \[\]/)
  assert.match(topicPage, /replyForm\.post\.attachment_ids = pendingAttachments\.value\.map/)
  assert.match(topicPage, /forumReplyDraftAdapter\.persist\(context, body\)/)
  assert.match(topicPage, /forumReplyDraftAdapter\.clear\(context\)/)
  assert.match(topicPage, /forumReplyDraftAdapter\.submitted\(context\)/)
})

test('identity changes, sign-out, and unmount invalidate delayed draft work', () => {
  assert.match(topicPage, /\[\(\) => page\.props\.auth\.user\?\.id, \(\) => props\.topic\.id\]/)
  assert.match(topicPage, /userId === previousUserId\s+&& topicId !== previousTopicId\s+\) \{\s+flushReplyDraftSave\(true\)/)
  assert.match(topicPage, /const draftUrl = activeReplyDraftUrl/)
  assert.match(topicPage, /\(!allowDetachedContext && !isCurrentReplyDraft\(context\)\)/)
  assert.match(topicPage, /invalidateReplyDraft\(\)\s+resetReplyDraftForm\(\)\s+const generation = replyDraftGeneration/)
  assert.match(topicPage, /await nextTick\(\)/)
  assert.match(topicPage, /\{ flush: 'sync' \}/)
  assert.match(topicPage, /if \(!replyDraftMounted \|\| generation !== replyDraftGeneration \|\| !isCurrentReplyDraft\(context\)\) return/)
  assert.match(topicPage, /onForumReplyDraftsInvalidated\(\(reason\) => \{\s+invalidateReplyDraft\(\)\s+if \(reason === 'clear'\) resetReplyDraftForm\(\)/)
  assert.match(topicPage, /onUnmounted\(\(\) => \{\s+flushReplyDraftSave\(\)\s+replyDraftMounted = false\s+invalidateReplyDraft\(\)\s+removeReplyDraftCleanup\?\.\(\)/)
  assert.match(topicPage, /clearTimeout\(draftSaveTimer\)/)
  assert.match(topicPage, /draftSaveRequest\?\.abort\(\)/)
  assert.match(topicPage, /if \(!replyDraftReady \|\| !context \|\| !isCurrentReplyDraft\(context\)\) return/)
  assert.match(topicPage, /if \(!replyDraftReady \|\| generation !== replyDraftGeneration \|\| !isCurrentReplyDraft\(context\)\) return/)
  assert.match(topicPage, /const draftUrl = props\.replyDraftUrl/)
  assert.doesNotMatch(topicPage, /fetch\(props\.replyDraftUrl/)
  assert.match(topicPage, /persistReplyDraftToServer\(draftUrl, body, attachmentIds, request\.signal\)/)
  assert.match(topicPage, /if \(draftSaveRequest === request\) draftSaveRequest = null/)
  assert.match(topicPage, /persistReplyDraftToServer\(draftUrl, '', \[\], request\.signal\)/)
  assert.match(topicPage, /flash\?\.post_create_succeeded !== submissionToken\) return/)
  assert.match(topicPage, /if \(!replySubmitted && generation === replyDraftGeneration && isCurrentReplyDraft\(context\)\) \{\s+scheduleReplyDraftSave\(\)/)
  assert.match(topicPage, /pendingAttachments\.value\.map\(\(item\) => item\.id\), undefined, true/)
})
