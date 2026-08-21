# User self-service remediation plan

Status: implementation baseline for the current local remediation pass

## Ownership and delivery path

- **Owner: CE.** The affected account, identity, community, commerce, navigation and localization behavior is shared platform functionality. It must not be reimplemented in EE or EE-PVP.
- **Delivery path:** implement and verify in CE, commit the CE history, then merge that history normally through `CE -> EE -> EE-PVP`. Downstream layers may add adapters only when a product-specific integration is genuinely required.
- **UI constraint:** use the product's existing component library and established portal primitives. Do not create a second button, card, form, dialog or focus system in page-scoped code.
- **Language ownership:** shared customer-facing copy belongs to the CE locale packages. Controllers and services return stable codes or translated messages; no new raw English strings may leak into the Chinese UI.
- **Motion constraint:** no gradient decoration and no hover/focus animation that changes a card's position or layout. Focus indicators appear for actual keyboard focus, not as a permanent decorative outline.

## Scope boundary

This pass covers shared, non-PVP-testing user journeys that are currently broken, incomplete or structurally misleading.

PVP test-domain product work is intentionally deferred: test applications and queues, leaving a test queue, in-test incidents/complaints, evidence correction, test review/reconsideration and sanction-appeal workflow changes. Deferring those features does **not** defer automated regression tests or browser acceptance for the shared changes in this plan.

## Delivery sequence

1. Replace the account link wall with a real account dashboard and establish the destination-page information architecture.
2. Complete identity self-service: profile editing and authenticated password change.
3. Repair commerce failure handling and refund self-service.
4. Complete community ownership loops for messages, topics, profile activity and notifications.
5. Complete product review and question/answer ownership loops.
6. Run focused server, frontend and browser validation in CE; commit only passing upstream work.
7. Merge the exact CE history through EE and EE-PVP, validate each layer, then leave the EE-PVP local service available for review.

## Functional requirements

### A. Account dashboard and navigation

#### Problem

The current `/app/account` page is a sitemap rendered as large equal-weight buttons. It repeats navigation, lacks identity and state, creates excessive whitespace and gives rare settings the same priority as urgent user tasks.

#### Required page model

The account page is an **overview and launch point**, not a replacement for every destination page.

1. **Identity summary**
   - Show avatar, display name, username and the minimum useful account metadata already available to the signed-in user.
   - Show the primary Minecraft identity when Minecraft is enabled, or a clear unbound state and one action to bind it.
   - Provide primary actions for editing the profile, managing security and managing Minecraft identities.
2. **Actionable status**
   - Show only real, server-derived state: unread private messages, unread notifications/topics, saved drafts, active sessions and security setup where those data exist.
   - A zero count is rendered as a quiet normal state, not as a large empty card.
   - Items requiring attention are visually distinguishable without gradients, movement or permanent focus rings.
3. **Recent/high-frequency destinations**
   - Keep high-frequency community actions compact and scannable.
   - Do not render every destination as a full-width button. Use the component library's list, description, badge, avatar, link and compact action patterns.
4. **Settings destinations**
   - Profile, password/security, sessions, privacy/preferences, blocked/ignored users, data export and Minecraft management remain independent pages with their own forms and explanations.
   - Rare forum utilities (watched tags, bookmarks and similar tools) live in one compact secondary section rather than dominating the dashboard.
5. **Responsive behavior**
   - Desktop uses a balanced two-column information layout only where content justifies it.
   - Tablet/mobile collapses to one logical reading order without horizontal overflow, clipped text or empty grid columns.
   - Chinese and English labels may wrap without changing control alignment or pushing the page wider than the viewport.

#### Acceptance criteria

- The first viewport answers who the user is, whether anything needs attention and where the three primary account actions are.
- No group contains a wall of equal-width navigation buttons.
- Every displayed count/state comes from persisted server data or existing shared page props; there are no invented placeholder metrics.
- Keyboard focus is visible only when appropriate, and hover/focus never changes element position.
- Simplified Chinese remains selected while navigating into and back from every linked account destination.

### B. Identity profile self-service

1. Add a signed-in profile page for the fields ordinary users are already allowed to own: display name and locale. Expose time zone only when the request/display pipeline actually applies it; a stored-but-unused selector is not a completed feature.
2. Username, account role and other privileged identity fields remain read-only and are not accepted from the client.
3. Trim the display name, store blank as `nil`, allow Unicode, reject control characters and enforce a 64-character limit. Validate locale against the canonical available-locale catalog. If time zone is delivered, validate an IANA identifier from a shared catalog rather than accepting free text.
4. Persist locale changes to the canonical user preference and synchronize the Rails session plus the shared frontend locale preference. The current session takes precedence over the user record, so updating the database alone is incorrect.
5. Successful save returns to a stable page state with a localized confirmation and refreshed shared user data.

#### Acceptance criteria

- A user can update each delivered field and see it after a full reload and a later login.
- Crafted requests cannot update privileged fields or another user.
- Invalid locale/time-zone/display-name values do not partially save; no-op saves do not create misleading audit events.

### C. Authenticated password change

1. Add a distinct security action for signed-in users; it must not redirect them into the logged-out password-reset flow.
2. Require the current password plus new password and confirmation. When TOTP is enabled, reuse the existing sensitive-action verifier and require a TOTP or recovery code.
3. Apply the canonical password policy and localized, field-specific errors.
4. On success, keep the initiating browser usable and revoke every other active session through the canonical session revocation method; clearly tell the user what happened. If the current session cannot be identified, fail closed.
5. Record the security event using the existing audit/security event mechanism without recording password material.
6. Clear stale password-reset/failed-login state on success, send the established security notification email and rate-limit repeated failures using the existing abuse-control primitive.
7. Profile, password and the existing email/TOTP security pages return `Cache-Control: private, no-store`.

#### Acceptance criteria

- Wrong current password, weak password and mismatched confirmation are distinguishable and do not change credentials.
- The new password works, the old password does not, and no password value appears in logs or response props.
- Direct access by a logged-out visitor returns to sign-in safely.

### D. Commerce order failure and refund lifecycle

1. Remove the unused parallel `OrdersController#new/#create` path and its customer `orders#create` route. The established Checkout controller remains the only order-creation authority, including promotion, gift-card, shipping and inventory validation. If a compatibility endpoint must remain, it may only redirect to checkout and must not create an order itself.
2. Replace raw refund English with CE locale keys and stable service/controller error mapping.
3. Let the order owner withdraw a **customer-requested, pending, not-yet-processed** refund request. Add a distinct `withdrawn` terminal state; do not overload rejected/failed.
4. Withdrawal must be atomic, idempotent, authorized and audited. Lock in the same order as refund processing so a customer withdrawal and staff approval cannot both win. Once approved or provider processing has begun, withdrawal is rejected and never calls the payment provider.
5. The order detail UI shows the withdrawal action only while it is valid and refreshes the refund timeline after success.

#### Acceptance criteria

- Failed order creation returns a 4xx/form state or redirect with useful feedback, never a 500.
- Chinese users see Chinese refund feedback for missing payment, an existing pending request and no refundable balance.
- Another user cannot view or withdraw the request; repeated withdrawal cannot create contradictory states.
- Pending, approved and completed refunds all reserve refundable balance consistently in customer and staff views; a withdrawn refund releases it.

### E. Private-message lifecycle

1. Move report creation out of the controller into one canonical transactional service. It owns the target allowlist, access policy, rate limit, pending-report deduplication, audit/event emission and an immutable evidence capture.
2. Add a one-to-one, encrypted, append-only report-evidence record. It stores only the minimum normalized snapshot, subject revision, capture time and digest needed for review. Database update/delete protection is required; ordinary audit metadata must never contain private-message bodies.
3. Replace hard-coded Chinese report reasons with locale keys.
4. Allow a participant to report a specific message sent by somebody else while they are still a conversation participant. Missing and unauthorized targets use non-enumerating responses.
5. Add a dedicated private-conversation-report review permission. Ordinary section moderators do not inherit access to private-message evidence. Evidence reveal is explicit, `private, no-store`, and itself audited; case lists and notifications do not expose message bodies.
6. Preserve message revisions when a sender edits content; use row locking plus an expected revision to reject stale edits. A report always displays the captured version even after the visible message is edited or deleted.
7. Support attachments by extending the established scanned upload and proxy-download pipeline. An attachment has at most one parent (post or message); message access requires a clean scan, a visible message and current conversation membership.
8. Message creation and attachment binding are one transaction. Cross-user/cross-conversation IDs, unclean files or concurrent double binding roll the entire send back and emit no notification. Drafts retain pending attachment IDs until send or expiry.
9. Sender deletion remains a soft presentation action consistent with conversation retention and moderation evidence. It must not erase an existing report snapshot.

#### Acceptance criteria

- Only participants can read, edit, delete or report messages in their conversation.
- A report retains enough immutable evidence for staff even if the visible message is later edited/deleted.
- Attachment download URLs cannot be used by nonparticipants.
- A removed group participant immediately loses attachment access; unresolved report/legal-hold evidence prevents attachment purge.
- Reviewers without the dedicated private-report permission cannot discover the report or reveal its content.

### F. User-owned community content

1. **Own topic deletion:** the topic author may request deletion only for a normal visible topic with no published reply by another user. Archived, global-announcement, commerce-managed, locked, reported, held or staff-managed topics are rejected. Reuse the data-governance soft-delete lifecycle; never directly hard-delete posts, attachments or evidence.
2. **Profile posts/comments:** only the original author can edit published content. Wall owners and moderators may retain their removal/moderation rights but may not rewrite another person's words. Edits use an expected revision, reapply creation-time content restrictions, retain report evidence and do not resend creation notifications.
3. **Notifications:** users can hard-delete one notification from their own inbox without affecting the underlying event or another user's notification. Add pagination/cursor access before exposing the action so records beyond the current 100-item/30-group/5-item truncation remain reachable. Web and write-enabled API routes use owner-scoped lookup; read-only API keys cannot delete.

#### Acceptance criteria

- Ownership, lock/hold states and stale/concurrent updates are enforced server-side.
- Deleted content does not break topic/profile page rendering or counts.
- Direct requests against another user's records return the established forbidden/not-found behavior.
- A topic with another user's published reply is not author-deletable; the user is directed to close it or contact staff instead.
- Deleting an unread notification updates its visible unread count, and old notifications remain individually reachable through pagination.

### G. Product reviews and questions/answers

1. Review editing and deletion already exist; repair their lifecycle instead of creating a duplicate feature. Split `published`, staff `hidden` and author `deleted` states so an author-deleted review can be deliberately republished while a moderator-hidden review cannot be self-restored.
2. Separate create and update semantics, revalidate rating/body/photos, and make attachment editing explicit: retain selected existing photos plus validated new uploads, with a maximum of three in total. Aggregate ratings count only published reviews.
3. Treat a forum post created from a review as an independent snapshot unless a separate, explicit synchronization design is approved. The review UI must explain that editing/deleting the review does not silently rewrite or delete the forum post.
4. A question author can edit or delete their own question. Deletion is a tombstone and never physically cascades answers; editing retains an audit/revision marker.
5. Answers gain explicit published/staff-hidden/author-deleted states. An official answer may be edited only by its author while that actor still holds the official-answer permission.
6. Hiding/restoring a parent question never automatically restores an answer that was independently hidden or deleted. Helpful votes and public counts exclude hidden/deleted answers.
7. UI actions appear only when allowed, but server authorization remains authoritative.

#### Acceptance criteria

- Another customer cannot mutate the content.
- Aggregate ratings and visible counts remain correct after edit/delete/moderation transitions.
- Product pages remain renderable when a question or answer is tombstoned.
- Cross-product question/answer identifiers return not found instead of mutating content through a mismatched product URL.

## Cross-cutting requirements

- **Authorization:** every mutation is scoped to `current_user` and rechecked server-side; hiding a button is never the security boundary.
- **Concurrency/idempotency:** destructive or state-transition actions reject stale state and tolerate safe retries.
- **Evidence/audit:** security, commerce and moderated-content transitions create existing audit/event records with no secrets.
- **Accessibility:** controls have programmatic names; keyboard order follows visual order; dialogs restore focus; status is not conveyed by color alone.
- **Localization:** all new UI, validation, flash and empty-state copy is present in both `zh-CN` and `en`, under the owning CE namespace.
- **Performance:** account summaries use bounded aggregate queries and eager loading; no per-card network waterfall or N+1 query is introduced.
- **Compatibility:** no CE page imports EE-PVP concepts and no PVP route is required for shared account pages to render.

## Verification matrix

- Focused Rails controller/service/model tests for each authorization and state transition.
- Frontend typecheck/build plus focused component/page tests where the repository already has a harness.
- Locale-key parity and raw-English regression checks.
- Browser acceptance at desktop and narrow viewport for account, profile, security, order/refund and representative community flows.
- Real Microsoft Edge final pass for layout, language persistence, keyboard focus and main mutations.
- Downstream smoke verification after each ordinary merge into EE and EE-PVP.
