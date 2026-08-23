# Commerce customer payment dispute lifecycle

## Ownership

- Owner: CE.
- Reason: payment-dispute identity, financial locking, refund reconciliation, evidence retention, audit, notifications, and entitlement risk holds are shared Commerce platform capabilities. EE and EE-PVP must inherit this history through ordinary `CE -> EE -> EE-PVP` merges and may add only edition-owned adapters.
- Application owner: Commerce under `/app/store/orders/:id`. This target does not change the Commerce Orders Index, application boundaries, PortalLayout, or any EE/PVP surface.

## Product problem

CE can ingest provider disputes and gives staff an internal dispute workbench, but the order owner has no reachable way to open a payment dispute, understand its lifecycle, add retained evidence, or withdraw an early mistaken case. Reusing the provider path as a second record would double-count exposure and repeat entitlement holds; exposing the staff serializer would leak internal notes and protected payment data.

## Functional requirements

### Ownership and reachability

- Only the signed-in owner resolved through the order public id may create, view, add evidence to, or withdraw a customer dispute.
- All customer mutations use dedicated order-scoped routes, private no-store responses, stable public ids, bounded parameters, and non-enumerating not-found behavior.
- The order detail contains the entry point and current case. The Orders Index and global navigation remain unchanged.

### Create and state lifecycle

- A succeeded payment on a paid/processing/fulfilling/fulfilled/completed order is eligible when positive payment value remains after reserved refunds and existing dispute exposure.
- Creation is blocked while a refund is pending, approved, or provider-unknown. Refund requests are likewise blocked while an active dispute owns financial exposure.
- A bounded request id plus immutable request fingerprint makes retries converge. The mutation locks order, payment, refunds, and disputes in the established financial order and permits at most one customer-origin case per payment.
- Creation records the customer origin explicitly on the existing `Commerce::Dispute`, creates an immutable customer event and audit entry, allocates only the available exposure, freezes order-derived rights through `RightsPolicy`, and creates one localized durable in-app notification.
- A later provider webhook binds its provider dispute identity to the unique unbound customer case under the same payment lock. It must update the existing case rather than create a second dispute, liability, timeline, or rights hold.

### Public timeline and privacy

- The order owner sees a localized status, amount, rights-impact label, evidence deadline when present, public timeline, and their SecureEvidence attachments.
- The customer serializer uses an explicit public event-type allowlist. It never returns staff/internal event notes, actors, request ids, raw metadata, provider payment/dispute identifiers, risk scores, assignees, evidence hashes, audit data, or staff-only evidence.
- Customer-authored descriptions are returned only from customer-origin events owned by that order user and remain bounded. Channel events are translated to a safe status summary rather than exposing provider payloads.

### Evidence

- Register `commerce.dispute` with CE `SecureEvidence`; do not use the legacy plaintext staff evidence snapshot or create another upload store.
- Allow the order owner to add evidence only while the customer case is active. Recheck ownership and state on upload, scan-status read, and download.
- Enforce the existing managed upload inspection, malware scan, quota, private download, and retention controls. The customer sees only attachments they uploaded for that exact dispute; staff access still requires the existing sensitive-dispute permission.
- Evidence upload is independently idempotent. Pending or quarantined evidence is not downloadable, and case withdrawal never deletes retained evidence.

### Withdrawal, refunds, rights, and notifications

- The owner may withdraw only a customer-origin case that is still `open` or `evidence_required` and has not been bound to a provider case or advanced to submission/review.
- Withdrawal is an explicit idempotent transition to `withdrawn`, releases liability, retains the record and evidence for seven years, restores only the dispute risk hold, audits the transition, and notifies the owner once.
- Completed refunds continue to call `RebalanceExposure`. A full refund may release dispute liability but must never let dispute restoration reactivate entitlements or memberships revoked by the refund lifecycle.
- Non-stale provider state changes create one localized customer notification keyed to the immutable dispute event; retries do not duplicate it. Notification deep links always return to the owned order detail.

## State and idempotency contracts

- Customer create: no case -> `open`; an identical request replays the same public case; a changed payload under the same request id fails.
- Customer withdrawal: `open | evidence_required -> withdrawn`; replay succeeds only for the same owner and request fingerprint.
- Provider binding: one active unbound customer case + first provider identity -> the same case with provider identity; exact webhook replay returns its existing event.
- Provider progression remains owned by `ApplyChannelEvent`: `open -> evidence_required -> evidence_submitted -> under_review -> won | lost | withdrawn` with existing stale-event protection.
- Lock order is order -> payment -> refunds/disputes -> rights subjects. Terminal customer states are never reopened by a delayed customer request.

## Implementation task list

- [ ] Add explicit customer-origin identity, timestamps, foreign key, and uniqueness/index contracts to `Commerce::Dispute`.
- [ ] Add idempotent create and withdraw services with financial locks, refund/exposure checks, rights policy calls, immutable events, auditing, and notifications.
- [ ] Bind provider channel events to the unique unbound customer case and notify the owner only for newly applied public state changes.
- [ ] Prevent refund requests from racing an active dispute; preserve refund-owned revocation when dispute exposure is restored after a completed full refund.
- [ ] Register the Commerce dispute SecureEvidence subject with owner/state authorization, staff-sensitive download access, limits, and seven-year retention.
- [ ] Add order-owned controller/routes and a strict customer serializer that omits every internal note and protected identifier.
- [ ] Add the Commerce order-detail case panel using shared Arco `@mcweb/ui`, including create, status/timeline, evidence upload/status, and conditional withdrawal.
- [ ] Add Commerce-scoped Simplified Chinese and English copy without modifying shared application-boundary locale files.
- [ ] Add service/request/model/serializer/component test source for ownership, retry conflict, refund/webhook/rights convergence, evidence authorization, notification dedupe, and internal-note non-disclosure.
- [ ] Leave database, concurrency, test, build, and browser execution to CNB and the main task; do not push.

## Acceptance matrix

- Ownership: another account gets 404 for case mutation and SecureEvidence access, and no dispute data appears in its order props.
- Reachability: an eligible owner can open the panel directly from order detail, submit once, refresh, attach evidence, and withdraw only while allowed.
- Retry: duplicate create, upload, withdraw, webhook, and notification delivery converge; a reused key with changed input fails.
- Finance: in-flight/provider-unknown refunds and active disputes cannot reserve the same payment amount; completed refunds cap liability; no payment can be over-allocated.
- Rights: create freezes once; webhook replay does not duplicate actions; withdrawal/zero exposure clears only the risk hold; a full refund remains revoked.
- Privacy: staff notes, actor identity, raw event metadata, provider references, staff evidence, and sensitive risk data are absent from every customer response.
- Evidence: only the owned active case accepts uploads; only scan-clean owned evidence downloads; retained evidence survives case withdrawal.
- Notification: each new customer-visible case event yields at most one localized persistent notification with an owned order deep link.
