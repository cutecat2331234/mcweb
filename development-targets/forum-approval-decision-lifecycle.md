# Forum approval decision lifecycle

## Ownership

- Owner: CE.
- Reason: pending-content reachability, section-moderator authorization, approval decisions, author notifications, and moderation audit records are shared Forum platform capabilities. EE and EE-PVP must inherit the same implementation through ordinary `CE -> EE -> EE-PVP` merges.
- Application owners: scoped moderators work in the Forum `/app` queue; administrators may use the Admin queue. Both surfaces must invoke the same CE decision services and expose the same functional guarantees.

## Product problem

The Forum and Admin approval queues each load only the newest 100 pending posts and expose no pagination. Once a permitted moderator has more than 100 pending items, older work remains counted in navigation but cannot be reached or decided from either supported interface.

Rejection is also currently a one-click POST with no reason input. The shared service accepts a blank reason, changes the post to hidden, and sends only a generic author notification. This leaves the author without an actionable explanation and makes an accidental destructive decision too easy.

## Functional requirements

### Complete queue reachability

- Paginate the permission-scoped pending-post relation in both Forum and Admin queues; do not materialize a global queue before authorization.
- Keep the stable pending ordering across pages and expose the total permitted count and previous/next navigation.
- Preserve the current queue page when a moderator opens a detail, approves an item, rejects an item, or receives a validation error.
- If a decision removes the final item from the current page, recover to the new last page instead of leaving the moderator on an empty out-of-range queue.
- A stale item that another moderator already decided must fail safely and return the operator to a reachable queue or detail state without changing the newer decision.

### Reasoned rejection

- Require a non-blank, bounded rejection reason at the CE service boundary so Admin, Forum, plugin, and future callers cannot bypass the contract.
- Show an explicit reason form and confirmation before rejection in the Forum queue and Admin detail; the existing topic-detail moderation action must collect the same reason before submission.
- Deliver the exact bounded reason to the author through the existing persistent notification channel and retain it in the immutable audit record.
- Approval remains a separate explicit action and never accepts or reuses rejection form state.
- Validation failure must leave the post pending and present an actionable localized error to the moderator.

### Authorization and state safety

- Continue authorizing every queue and decision through `Community::SectionModeration`; pagination parameters cannot widen the visible section set.
- Decide only a currently `pending_approval` post while holding the existing topic/post locks.
- Do not expose hidden topics, attachments, internal moderator identities, or another section's queue through pagination or return-path parameters.
- Accept only same-origin, application-owned queue return paths; untrusted return targets fall back to the canonical queue.
- Keep notification persistence and the audit write in the rejection transaction. External webhook dispatch occurs only after the database decision succeeds and must not erase a committed operator result.

## Interface requirements

- Reuse the existing Portal and Arco/Admin components; this task does not redesign either application.
- Support keyboard submission and cancellation, an associated reason label/error, disabled duplicate submission, and localized Simplified Chinese/English text.
- The Forum queue receives its own pagination controls. The Admin queue reuses the existing generic pagination contract.

## Implementation task list

- [x] Paginate the permission-scoped pending relation in the Forum and Admin controllers.
- [x] Add pagination and queue-return props without trusting arbitrary return URLs.
- [x] Add reason entry and confirmation to the Forum moderation queue, topic moderation action, and Admin approval detail.
- [x] Enforce bounded non-blank reasons in `Community::RejectPost` before any state mutation.
- [x] Persist rejection notification and audit effects transactionally; dispatch the external forum event after the decision commit.
- [x] Add service, controller, pagination, authorization, stale-decision, i18n, and interface contract coverage for CNB.
- [x] Run only Ruby syntax, diff whitespace, route/reference, and focused static consistency checks locally.
- [ ] Merge the committed CE history normally into EE and then EE-PVP; do not copy, cherry-pick, squash, or recreate it downstream.
- [ ] Run Rails tests, TypeScript checks, builds, database/concurrency tests, and desktop/mobile browser acceptance in CNB.

## Acceptance matrix

- Reachability: a moderator with 101 or more permitted pending posts can reach and decide every item across pages in both interfaces.
- Scope: a section moderator never receives another section's rows, counts, detail, attachment, or mutation access.
- Reason: blank and over-limit reasons fail before state mutation; a valid reason is visible in the author's persistent notification and the audit event.
- Retry/stale state: duplicate or concurrent decisions never overwrite the first terminal decision and return a stable error/redirect.
- Navigation: page context survives detail, validation failure, approve, reject, refresh, and back/forward navigation.
- Delivery: EE and EE-PVP contain the exact CE commits through ordinary merges, with no downstream copy of the implementation.
