# Community report lifecycle

## Ownership

- Owner: CE.
- Reason: reporting, evidence retention, reporter follow-up, and moderation appeals are shared public-platform safety capabilities. EE and EE-PVP may add adapters, but must inherit this state machine through normal `CE -> EE -> EE-PVP` merges.
- Application owner: Forum. Reporter and appellant pages resolve only through the Forum entry; staff decisions resolve through the Staff/Admin applications after the application-boundary work lands.

## Product problem

The existing forum report flow ends immediately after submission. A reporter cannot see whether a report is pending or decided, add relevant information, withdraw an accidental pending report, or request reconsideration. A user affected by an upheld moderation action also lacks a privacy-safe appeal path. Staff decisions are recorded internally but are not delivered as a safe user-facing outcome.

## Delivery status

- Phase 1 was delivered by `7068f3af`: the private reporter case center, immutable supplements, explicit pending withdrawal, safe public outcomes, durable outcome notifications, and single/bulk staff decision integration are implemented.
- Phase 2 implementation is complete on CE: non-enumerable public identifiers, affected-user attribution, role-isolated reconsideration/appeal state machines, SecureEvidence attachment binding, and user/staff appeal interfaces are implemented. Database, concurrency, full-build, and browser acceptance remain assigned to CNB before release.

## Functional requirements

### Reporter case center

- Provide private index and detail pages containing only reports owned by the signed-in reporter.
- Show the reported target as a stable, privacy-safe label even if the original content later becomes hidden or deleted.
- Show submitted time, current state, last state change, and a public outcome code. Never expose the reviewer identity, internal review note, other reporters, moderation evidence, or protected target data.
- Keep direct links private, non-indexable, and `Cache-Control: private, no-store`.

### Pending report changes

- A reporter may append bounded text supplements while the report is pending. Supplements are immutable after creation and remain part of the audit/evidence record.
- A reporter may explicitly withdraw only their own pending report. Withdrawal is idempotent, releases the pending deduplication slot, does not delete evidence, and never behaves as a toggle.
- All mutations use row locking, optimistic version checks, bounded idempotency keys, stable error codes, and audit records.

### Decision delivery

- Staff decisions map to a small public outcome vocabulary maintained by CE. Internal notes and exact penalties are never copied to user-visible fields.
- A durable in-app notification is created once for each final reporter outcome and links to the private report detail page.
- Notification visibility is revalidated against the report owner; stale or forged metadata fails closed.
- Bulk target resolution produces one outcome per owned report without leaking the number or identity of other reporters.

### Appeals

- A reporter may request reconsideration after a dismissed decision.
- A user directly affected by an upheld report may appeal the resulting moderation action without learning the reporter identity, report reason, or evidence.
- `affected_user_id` is resolved through an explicit supported-target resolver and frozen when an actioned decision is committed. Unsupported or ambiguous targets do not acquire a subject appeal right. Staff cannot supply an arbitrary user id.
- Appeals are separate immutable records with an explicit appellant role, reason, state timeline, lock version, and one active appeal per appellant/report/role.
- The server idempotently creates a private, non-reviewable appeal draft before uploads. A draft is visible only to its appellant, expires on a bounded schedule, and cannot appear in staff queues or notifications. It is the only valid `community.report_appeal` upload subject; clients cannot choose another subject identity.
- Reporter reconsideration and affected-subject appeal are separate authorization surfaces. A reporter cannot act as the subject, a subject cannot enter the reporter case, and a person who happens to have both identities must choose and remain within one role-specific case.
- Staff may uphold or overturn an appeal with a public outcome code and a separate internal note. Every transition is audited and notifies only the appellant.
- Resolving a subject appeal must not silently reverse unrelated moderation actions; reversal goes through the owning moderation service.
- Submit, cancel, and decide requests include an idempotency key, immutable request fingerprint, expected lock version, and fixed-order locking. Duplicate, concurrent, delayed, and out-of-order delivery converges without reopening a terminal state.

### Evidence and retention

- Reuse CE `SecureEvidence`; do not create another upload store.
- Accept at most 10 attachments per report or appeal, with existing size, type, decoded-content, malware scan, quota, authorization, and retention controls.
- Pending or failed scans are not downloadable. Authorization is rechecked for every upload, status read, and download.
- Draft uploads belong to exactly one subject and uploader. Appeal submission accepts only caller-owned, scan-clean attachment public IDs for that same appeal draft, locks them in deterministic order, and atomically seals immutable evidence associations while transitioning the draft to `submitted`. Report evidence sealing follows the same subject/uploader checks without rebinding attachments.
- Draft evidence may be discarded through the existing SecureEvidence discard lifecycle. Once sealed, an attachment cannot be discarded or rebound by a user.
- Cancelling or expiring an unsubmitted draft schedules its remaining attachments through the existing discard/retention lifecycle; it never fabricates a submitted appeal.
- Reports, supplements, appeals, decisions, evidence hashes, and audit events remain protected from account/content purge according to the existing retention and legal-hold rules.

### Interface requirements

- Use only the shared `@mcweb/ui`/Arco components and existing design tokens.
- No gradients, card movement, persistent focus decoration, hand-written selection borders, or explanatory development copy.
- Desktop and mobile layouts use the same information hierarchy. Keyboard order, focus visibility, labels, error association, and live status feedback must remain accessible.
- All user text belongs to the Forum locale domain in Simplified Chinese and English. Shared Account strings are used only for genuinely shared notification-shell concepts.

## State contracts

- Report: `pending -> withdrawn | reviewed | dismissed | actioned`.
- Supplement: append-only and accepted only while the report is `pending`.
- Appeal: `draft -> submitted -> under_review -> upheld | overturned | cancelled`; `draft -> cancelled` is allowed for abandonment/expiry, and user cancellation is otherwise allowed only before review starts. Drafts are not cases and never enter staff queues.
- Terminal states are never reopened by repeated, delayed, or out-of-order requests.
- External report and appeal routes use stable `public_id` values only. Internal numeric ids never appear in user, staff, notification, or evidence URLs.
- Appeal events and sealed evidence associations are append-only at both the model and database layers.

## Implementation task list

- [x] Add report lifecycle fields, supplements, constraints, indexes, retention-safe associations, and model contracts.
- [x] Add idempotent CE services for supplement, withdrawal, and single/bulk report decisions.
- [x] Add reporter-only controllers/routes/serializers with private caching and strict target labels.
- [x] Add Forum report center pages using the shared UI library and Forum language keys.
- [x] Connect staff report decisions and bulk decisions to public outcomes and durable notifications transactionally.
- [x] Register report outcome notification visibility policies and private deep links.
- [x] Add stable report `public_id`, safely resolved/frozen `affected_user_id`, and migrate every external report reference away from numeric ids.
- [x] Add `Community::ReportAppeal`, append-only events, sealed evidence associations, constraints, partial uniqueness, rollback support, and retention declarations.
- [x] Add an idempotent server-created appeal draft lifecycle with private ownership, expiry, discard, and atomic `draft -> submitted` evidence sealing.
- [x] Add idempotent appeal submit/cancel/decide services with role isolation, deterministic locks, optimistic versions, immutable fingerprints, auditing, and notifications.
- [x] Register `community.report` and `community.report_appeal` with `SecureEvidence`, including upload/download/discard authorization and the 10-attachment limit.
- [x] Add role-isolated user appeal/reconsideration navigation, index, detail, timeline, attachments, and safe notification deep links.
- [x] Add Staff/Admin appeal queues, detail, evidence access, and decisions without exposing protected reporter information or internal notes to users.
- [x] Add database/static/service/UI/i18n contracts for public ids, privacy, state transitions, attachment binding, retries, and concurrency.
- [ ] Merge the committed CE history normally into EE and then EE-PVP; downstream changes, if any, remain separate adapters.
- [x] Run focused static checks locally; run database, concurrency, attachment scanning, full build, Edge, desktop/mobile, and accessibility acceptance in cached CNB jobs.

## Acceptance matrix

- Ownership: another account receives 404 for report, supplement, appeal, and attachment URLs.
- Identifier safety: external routes, notifications, exports, and evidence subjects contain only stable public ids; guessed numeric ids never resolve.
- Retry safety: duplicate, concurrent, timed-out, and out-of-order mutation requests converge on the requested final state.
- Privacy: reporter, subject, ordinary staff, scoped moderator, PM reviewer, and administrator each receive only their allowed fields.
- Role isolation: dismissed-report reconsideration is available only to its reporter; actioned-report appeal is available only to its frozen affected user; neither surface reveals the other actor.
- Evidence: only clean caller-owned drafts for the same subject can be atomically sealed; pending, quarantined, foreign, rebound, over-limit, or discarded attachments fail closed.
- Draft safety: clients cannot forge an appeal subject; abandoned and expired drafts stay out of staff queues and release unsealed evidence through the existing discard/retention lifecycle.
- Decision loop: single and bulk decisions create exactly one persistent, localized outcome notification per affected owner.
- Retention: withdrawal and account closure do not erase protected evidence; final purge remains blocked by open cases or legal hold.
- Navigation: direct link, refresh, back/forward, Simplified Chinese, theme, and cross-application document navigation remain correct.
