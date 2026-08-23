# Identity security recovery mail lifecycle

## Ownership and status

- Highest reusable owner: **McWeb CE**.
- Scope: password-reset and TOTP-recovery security email delivery only.
- Status: source implementation complete; runtime verification is intentionally deferred to the parent task.
- Downstream rule: EE and EE-PVP inherit this CE history by ordinary merges; they must not copy the implementation.

## Excluded work

- Frontend application-boundary work, `PortalLayout`, frontend locale catalogs, Community, Commerce, PVP, and EE.
- TOTP enrollment and `Identity::EnableTotp` files.
- New user-facing pages or routes. The existing password-reset and TOTP-recovery request forms remain the bounded resend entry points.
- Local tests, builds, type checks, lint, syntax checks, browser checks, services, and CNB runs in this task.

## Baseline problem

Before this target, `Identity::ResetPassword` and `Identity::RecoverTotp` created a token and called
`MailDeliveryJob.perform_later` once. A committed token could therefore outlive a lost enqueue,
while operators had no durable, secret-safe lifecycle tying the request to delivery attempts.

## Requirements

- [x] Record the business request and a durable delivery intent in the same database transaction.
- [x] Reuse CE's `Operations::DurableEnqueue` ledger, recovery job, bounded retry policy, and permission-gated manual reopen rather than adding another outbox.
- [x] Use one shared identity handler for password reset and TOTP recovery; do not duplicate delivery state machines.
- [x] Persist recoverable token material only through encrypted model attributes. Intents, jobs, logs, and audits retain only stable intent identifiers, SHA-256 digests, purpose codes, and bounded error codes; they never retain the raw token.
- [x] Keep duplicate requests inside the resend cooldown idempotent: reuse the current token and dedupe key instead of creating another intent.
- [x] After the resend cooldown, rotate the token and intent so an older delayed worker can only skip a superseded token.
- [x] Keep the existing per-email/IP request limits. Public resend uses the existing recovery forms; exhausted delivery reopen remains restricted to `system.jobs.manage`, a selected public intent ID, and an audit reason.
- [x] Expose a stable product status vocabulary: `pending`, `sent`, and `failed`, derived from the append-only durable ledger and visible in the existing administrator jobs workspace.
- [x] Never deliver an expired, consumed, missing, or superseded token.
- [x] Consume each token at most once under a user row lock. Password reset and successful TOTP recovery revoke old sessions in the same credential-mutation transaction.
- [x] Audit anonymous request/resend and authenticated recovery completion without recording plaintext tokens, passwords, TOTP secrets, or recovery codes.
- [x] Clear encrypted recovery-token material when the token is consumed, when a password or email change invalidates it, when TOTP is disabled, or when the account is closed.

## State machines

### Delivery state

```text
                         enqueue/worker retry
                    +---------------------------+
                    |                           v
no request --issue--> pending --delivered-----> sent
                         |
                         +--attempt error------> pending
                         |                       (bounded backoff)
                         +--attempts exhausted-> failed

dead-lettered failed --authorized manual reopen + reason----> pending
skipped failed ---------------------------------------------> terminal
```

The CE durable ledger remains authoritative. Its operational states map as follows:

| Durable state | Identity status | Reopenable |
| --- | --- | --- |
| `pending`, `running`, `retrying` | `pending` | No; automatic lifecycle is still active |
| `succeeded` | `sent` | No |
| `skipped` | `failed` | No; the token is missing, expired, consumed, superseded, or otherwise terminal |
| `dead_lettered` | `failed` | Yes; only through the selected-ID, permission-checked, reason-audited staff task |

`sent` means the configured mail transport accepted the message. The handler deliberately retains
the existing `at_least_once` replay contract, so a process crash after transport acceptance may
produce a duplicate message but cannot make the token consumable twice.

### Token state

```text
none --issue--> current --successful recovery--> consumed
                    |\
                    | +--TTL elapsed------------> expired
                    +----resend after cooldown---> superseded --(new token current)
```

- A duplicate request during the cooldown reuses `current`; it does not create a new token or intent.
- A delayed worker holds the user row lock while it compares the encrypted token, current stored digest, and intent digest using constant-time comparison and hands the message to the transport. A concurrent resend cannot rotate the token between validation and delivery.
- `consumed`, `expired`, and `superseded` intents finish without sending the old secret.

## Implementation checklist

- [x] Add encrypted password-reset and TOTP-recovery token attributes to `User`.
- [x] Add the shared CE identity delivery handler and register it in the core durable-enqueue catalog.
- [x] Move both request paths to the shared transactional issue/dedupe lifecycle.
- [x] Add the existing administrator jobs workspace status table and reuse its permission-gated durable retry task.
- [x] Clear encrypted material from every existing invalidation path.
- [x] Add focused source tests for durable recording, duplicate requests, resend rotation, status mapping, bounded retries, secret exclusion, supersession, one-time consumption, session revocation, and rollback.
- [x] Review the final diff and commit only files owned by this target.

## Deferred verification

The implementation is not production-verified until the parent task runs the focused Rails tests,
database migration checks, queue-loss/recovery checks, and real mail-delivery acceptance after this
development-only commit. `db/schema.rb` must also be regenerated after the earlier-numbered,
concurrently developed migrations have landed; this target does not overwrite their existing schema work.
