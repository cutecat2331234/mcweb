# Forum group-conversation invitation lifecycle

## Ownership

- Owner: CE.
- Reason: private-conversation membership, history visibility, recipient policy, notification access, and invitation lifecycle are shared Forum platform and security contracts. EE and EE-PVP must inherit the same CE history through ordinary `CE -> EE -> EE-PVP` merges; neither downstream may copy or reinterpret this lifecycle.
- Application owner: the existing Forum messages application owns both the member inbox and the invitation response surface. The notification center may deep-link to that surface, but it does not own invitation state.

## Verified defect

- `Community::CreateGroupConversation` creates every named recipient as a `forum_conversation_participants` row before it creates the first message.
- `Community::AddConversationParticipant` also creates a participant row immediately and then emits an “added to conversation” notification.
- `Community::Conversation.for_user`, the HTML and API detail authorization, unread counters, attachment/message reads, and private-message notification access all treat a participant row as the membership boundary.
- Therefore a recipient who has never consented immediately receives the group in the primary inbox and can read the full message history. The existing `forum.conversation_invite` notification is only an after-the-fact notice; it is not an invitation.

## State and visibility contract

- Invitation states are `pending -> accepted | declined | expired | revoked`.
- `pending` reserves one group-capacity slot and is actionable only before `expires_at`, while the invitee remains eligible for private messages and has no block relationship with any current participant.
- `accepted` is written in the same transaction as the unique participant row. Only that participant row grants inbox, message, attachment, draft, unread, API, or future private-message notification access.
- `declined`, `expired`, and `revoked` are terminal for that invitation attempt. A later invitation creates a new attempt; terminal records are not reopened.
- Time expiry is enforced both at every response/read boundary and by a recurring cleanup job. A newly created block revokes still-pending invitations that would place either user in the same group, and acceptance independently rechecks all current participants under user and conversation locks.
- Before acceptance, an invitee may see only the group title, inviter name, expiry time, and accept/decline actions. No conversation URL, participant roster, message preview, message body, attachment, read state, or unread count is serialized.
- Declining or losing eligibility never creates a participant row. Stale notification content fails closed when its matching invitation is no longer actionable.

## Compatibility and exception boundary

- Existing participant rows are grandfathered as accepted membership. The migration does not reinterpret or remove existing members, archives, labels, stars, mute state, read state, creators, or message history.
- A conversation creator is still inserted directly as the initial participant. Existing members remain participants until the existing removal service removes them.
- Normal Forum controllers always issue invitations; they never request direct membership.
- A direct membership bypass is an explicit service-only mode reserved for an actor with the existing `forum.topics.lock` permission or an explicitly identified system operation. It is not inferred from a username, not exposed as a request parameter, and still fails closed on block, account, silence, warning, and capacity checks.
- Existing group invite-lock ownership remains intact: unlocked groups allow current participants to invite; locked or creator-only groups allow the creator or permitted staff. Pending invitations issued before a later lock remain actionable.
- Existing private-message policy remains an invitation-issuance prerequisite. Explicit acceptance is the invitee's consent, while current account eligibility, trust level, warning, silence, block, and capacity state are revalidated before membership is created.
- The configured group participant maximum counts current participants plus unexpired pending invitations, preventing invitation overbooking and acceptance races.
- Direct conversations are unchanged. The public/private conversation API continues to expose participants and history only through `Conversation.for_user`; pending invitations are intentionally not added to that API in this change.

## Implementation task list

- [x] Add a constrained CE invitation record with public identifiers, expiry, terminal timestamps, participant associations, and capacity scopes.
- [x] Change group creation and member addition to create pending invitations while keeping creator and explicit staff/system membership exceptions.
- [x] Add idempotent accept/decline services with fixed locking, capacity enforcement, expiry, eligibility, and block revalidation.
- [x] Revoke affected pending invitations when a block is created and expire stale invitations on a recurring schedule.
- [x] Add private Forum response routes/controllers and an inbox invitation panel that remains usable on narrow/mobile layouts without exposing conversation history.
- [x] Rework invite notifications and email delivery to deep-link to the response surface and revalidate invitation access at delivery/read time.
- [x] Add Simplified Chinese and English service, flash, notification, email, and client-interface strings.
- [x] Add model/service/integration/notification-access/mailer test source for privacy, transitions, idempotency, capacity, expiry, blocking, and explicit exceptions.
- [ ] Merge the eventual committed CE history normally into EE and then EE-PVP; downstream adapters, if any, remain separate downstream commits.

## Acceptance matrix

- Privacy: a pending invitee receives 404 for the conversation HTML/API/detail and cannot discover its messages, previews, attachments, roster, unread count, or drafts.
- Inbox: pending invitations appear only in the separate invitation panel; the primary conversation list remains participant-only.
- Accept: one accepted request creates exactly one participant and exposes history only after commit; duplicate requests converge without duplicate membership.
- Decline: one declined request creates no participant; duplicates converge and a later accept cannot reopen it.
- Expiry: boundary checks and scheduled cleanup make an expired invite non-actionable and hide its notification content.
- Block: a block revokes relevant pending invitations, notification content becomes unavailable, and an acceptance race cannot produce membership after the block wins the shared user lock.
- Capacity: participants plus actionable pending invitations never exceed the configured maximum, including concurrent sends and accepts.
- Exceptions: creator and grandfathered members keep access; only explicit permitted staff/system calls can bypass consent, and the web request surface cannot select that mode.
- Localization and mobile: both supported locales expose the same labels and outcomes, and invitation actions are reachable without a desktop-width header.
