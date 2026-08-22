# Community report lifecycle

## Ownership

- Owner: CE.
- Reason: reporting, evidence retention, reporter follow-up, and moderation appeals are shared public-platform safety capabilities. EE and EE-PVP may add adapters, but must inherit this state machine through normal `CE -> EE -> EE-PVP` merges.
- Application owner: Forum. Reporter and appellant pages resolve only through the Forum entry; staff decisions resolve through the Staff/Admin applications after the application-boundary work lands.

## Product problem

The existing forum report flow ends immediately after submission. A reporter cannot see whether a report is pending or decided, add relevant information, withdraw an accidental pending report, or request reconsideration. A user affected by an upheld moderation action also lacks a privacy-safe appeal path. Staff decisions are recorded internally but are not delivered as a safe user-facing outcome.

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
- Appeals are separate immutable records with an explicit appellant role, reason, state timeline, lock version, and one active appeal per appellant/report/role.
- Staff may uphold or overturn an appeal with a public outcome code and a separate internal note. Every transition is audited and notifies only the appellant.
- Resolving a subject appeal must not silently reverse unrelated moderation actions; reversal goes through the owning moderation service.

### Evidence and retention

- Reuse CE `SecureEvidence`; do not create another upload store.
- Accept at most 10 attachments per report or appeal, with existing size, type, decoded-content, malware scan, quota, authorization, and retention controls.
- Pending or failed scans are not downloadable. Authorization is rechecked for every upload, status read, and download.
- Reports, supplements, appeals, decisions, evidence hashes, and audit events remain protected from account/content purge according to the existing retention and legal-hold rules.

### Interface requirements

- Use only the shared `@mcweb/ui`/Arco components and existing design tokens.
- No gradients, card movement, persistent focus decoration, hand-written selection borders, or explanatory development copy.
- Desktop and mobile layouts use the same information hierarchy. Keyboard order, focus visibility, labels, error association, and live status feedback must remain accessible.
- All user text belongs to the Forum locale domain in Simplified Chinese and English. Shared Account strings are used only for genuinely shared notification-shell concepts.

## State contracts

- Report: `pending -> withdrawn | reviewed | dismissed | actioned`.
- Supplement: append-only and accepted only while the report is `pending`.
- Appeal: `submitted -> under_review -> upheld | overturned | cancelled`; cancellation is allowed only before review starts.
- Terminal states are never reopened by repeated, delayed, or out-of-order requests.

## Implementation task list

- [ ] Add report lifecycle fields, supplement records, appeal records, constraints, indexes, retention declarations, and model contracts.
- [ ] Add idempotent CE services for supplement, withdrawal, decision notification, appeal submission/cancellation, and appeal decision.
- [ ] Add reporter-only controllers/routes/serializers with private caching and strict target labels.
- [ ] Add Forum report center pages using the shared UI library and Forum language keys.
- [ ] Connect staff report decisions and bulk decisions to public outcomes and durable notifications transactionally.
- [ ] Register report/appeal notification visibility policies and private deep links.
- [ ] Register Report and ReportAppeal subjects with `SecureEvidence`, including per-subject authorization and the 10-attachment limit.
- [ ] Add staff appeal queues and decision actions without exposing protected reporter information to subjects.
- [ ] Merge the committed CE history normally into EE and then EE-PVP; downstream changes, if any, remain separate adapters.
- [ ] Run focused static checks locally; run database, concurrency, attachment scanning, full build, Edge, desktop/mobile, and accessibility acceptance in cached CNB jobs.

## Acceptance matrix

- Ownership: another account receives 404 for report, supplement, appeal, and attachment URLs.
- Retry safety: duplicate, concurrent, timed-out, and out-of-order mutation requests converge on the requested final state.
- Privacy: reporter, subject, ordinary staff, scoped moderator, PM reviewer, and administrator each receive only their allowed fields.
- Decision loop: single and bulk decisions create exactly one persistent, localized outcome notification per affected owner.
- Retention: withdrawal and account closure do not erase protected evidence; final purge remains blocked by open cases or legal hold.
- Navigation: direct link, refresh, back/forward, Simplified Chinese, theme, and cross-application document navigation remain correct.
