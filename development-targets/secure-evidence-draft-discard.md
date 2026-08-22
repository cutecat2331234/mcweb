# Secure evidence draft discard

## Ownership

- Owner: CE.
- Reason: uploader authorization, attachment quota accounting, scan/cleanup races, retention metadata, and subject registration are shared evidence-platform contracts. EE and EE-PVP may only register subject-specific “still unlinked” authorization callbacks after inheriting this CE primitive through ordinary `CE -> EE -> EE-PVP` merges.
- Scope boundary: CE does not know PVP dispute messages, reviews, sanctions, or any downstream join model.

## Product problem

An uploader can create an evidence attachment that fails scanning, remains quarantined, or is no longer wanted before it is linked to a submitted record. There is currently no authorized server-side way to abandon that unlinked draft. These records continue to consume the subject file limit and can leave the user unable to replace a bad upload. Client-only removal is misleading because the managed blob and quota remain active.

## Functional requirements

- Add an idempotent server-side discard action for secure-evidence attachments.
- Only the persisted uploader may discard an attachment, and only when the owning subject registrar explicitly confirms that the attachment is not linked to a durable domain record.
- A subject without a discard callback fails closed. Existing registrars remain source-compatible but do not gain discard permission implicitly.
- Repeated discard requests for an already `purge_pending` or `purged` attachment converge successfully for the same authorized uploader and subject.
- Discard transitions metadata to the existing `purge_pending` state, records an immutable `discarded` evidence event, and schedules the existing managed-upload cleanup path. Metadata and audit history are retained after the blob reaches `purged`.
- File-count and byte quotas count only active `pending`, `available`, and `quarantined` attachments. A successful discard releases quota immediately.
- Late or retried malware-scan work cannot move a discarded attachment back to `available` or `quarantined`, and cannot revive a cleanup-pending/cleaned upload.
- Attachment responses expose a server-derived `updated_at`; an authorized unlinked uploader may also receive a discard URL. Unauthorized and missing records remain indistinguishable.

## API and registration contract

- Extend `SecureEvidence::SubjectRegistry` with an optional callable `discard_authorizer`.
- The callback receives the resolved subject, attachment, and actor and returns true only when the subject adapter proves the attachment is still unlinked and discardable.
- `DELETE /app/evidence/attachments/:public_id` returns private, no-store JSON and never accepts a client-provided subject or uploader override.
- Download, scan-status, retention, and final purge authorization remain unchanged.

## Safety requirements

- Keep the existing lock order used by scanning and cleanup: managed upload first, then secure-evidence attachment.
- The discard callback runs while that attachment row is locked; downstream link writers must acquire the same attachment row lock before creating their durable association, so “link” and “discard” cannot both win.
- Record the discard event and state transition atomically; enqueue cleanup only after commit.
- Never delete immutable attachment metadata or event rows.
- Never use Git LFS as blob storage or dependency cache.
- Stable error codes must distinguish validation internally while the controller maps missing and unauthorized access to the same 404 response.

## Implementation task list

- [ ] Extend the subject registry and policy with an optional, fail-closed discard callback.
- [ ] Add `SecureEvidence::DiscardAttachment` with uploader ownership, subject resolution, unlinked proof, row locking, idempotency, event recording, and after-commit cleanup scheduling.
- [ ] Add the attachment destroy route/controller response and server-derived `updated_at`/discard URL serialization.
- [ ] Exclude `purge_pending`/`purged` attachments from active subject quotas.
- [ ] Harden scan claiming and scan-result synchronization against discard/cleanup races.
- [ ] Add `discarded` to model and database event vocabularies and deliver it through `schema.rb`.
- [ ] Cover owner/unlinked success, linked/non-owner denial, replay, quota release, late scan, cleanup metadata retention, private 404 behavior, and schema delivery.
- [ ] Merge the committed CE history normally into EE and EE-PVP; register downstream unlinked checks only in their owning repositories.
- [ ] Run lightweight syntax/static checks locally; defer database/concurrency/build/browser gates to cached CNB after the full development batch is complete.

## Acceptance matrix

- Authorization: owner + unlinked succeeds; owner + linked, another account, missing subject, and unregistered subject all fail closed.
- Retry safety: duplicate, concurrent, delayed, and post-cleanup DELETE requests converge without duplicate destructive effects.
- Quota: discarding one of a full subject’s active attachments permits its replacement immediately.
- Race safety: scan completion arriving before, during, or after discard never revives discarded evidence.
- Retention: the managed blob is removed through the existing cleanup service while attachment identity, hash, state timeline, and audit events remain queryable.
- Delivery: fresh schema load contains the expanded event constraint; downstream adapters can register without importing downstream concepts into CE.
