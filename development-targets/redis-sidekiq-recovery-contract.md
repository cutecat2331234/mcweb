# Redis / Sidekiq recovery contract

## Ownership and delivery boundary

- Owner: CE.
- Reason: queue durability, shared background-work admission, recovery, and operational health are platform contracts used by every edition. EE and EE-PVP must inherit this implementation through ordinary `CE -> EE -> EE-PVP` merges and may register only their own allowlisted downstream handlers.
- Scope: the Redis dependency used by Sidekiq, PostgreSQL durable-enqueue intents, a small set of critical CE producer paths, and read-only operations visibility.
- Excluded: PVP concepts, a second outbox, a caller-selected job class or queue, broad replacement of every `perform_later`, a new realtime transport, and UI redesign.
- Validation boundary: this task writes implementation and test source only. It does not run tests, builds, type checks, lint, syntax checks, `git diff --check`, browsers, or CNB; it does not commit or push.

## Verified runtime topology

Redis is not a general McWeb data store. The recovery contract must match the actual production topology instead of inventing dependencies:

| Concern | Current owner/store | Redis outage behavior required here |
| --- | --- | --- |
| Production cache | Solid Cache | No Redis-specific fallback is needed. Existing database-backed reads remain authoritative. |
| Session | Signed cookie store | No Redis session loss exists. Authentication state does not depend on Redis. |
| Abuse and sensitive-action limits | PostgreSQL `RateLimitCounter` and reservations | Security limits remain durable and fail according to their database contracts, independently of Redis. |
| Active Job / scheduled work | Sidekiq on Redis | Redis unavailability must be visible; critical work must first have a PostgreSQL intent or fail before the business transaction commits. |
| Notifications | PostgreSQL `Notification`; allowlisted durable web-push intent | The in-app notification remains readable. Push delivery may be delayed and reconverges from the durable intent. |
| Realtime | No CE Action Cable backend | There is no Redis pub/sub recovery path in CE. Clients use persisted reads/polling. |

## Problem statement

CE already has an append-only PostgreSQL durable-enqueue ledger, a frozen allowlist of handlers, bounded retries, a one-minute recovery sweep, and permission-gated manual reopen. However, several user-visible or safety-relevant producers still commit a durable `queued` business row and make a one-shot direct Sidekiq enqueue. A short Redis outage can therefore leave the UI reporting an accepted request that has no durable handoff. Queue health also loses Redis counters exactly when operators most need to see how much database-backed work is awaiting recovery.

## Functional requirements

- [x] Keep `Operations::DurableEnqueue` as the only shared outbox. Extend its boot-frozen handler allowlist; never persist a Ruby constant, caller-selected queue, arbitrary arguments, or secret payload.
- [x] Record each migrated business row and its enqueue intent in the same PostgreSQL transaction. If the intent cannot be recorded, roll back the write and return the stable translatable code `background_processing_unavailable`.
- [x] Treat a Redis enqueue failure after commit as delayed acceptance, not completed work. The durable business status remains `queued` and the append-only intent remains recoverable.
- [x] Migrate the initial account-data export, account-data export retry, and finance export request paths. Their existing `queued`/`running`/terminal states remain the user-facing truth.
- [x] Migrate creation of a Minecraft node operation because backup, restore, recovery, sync, and metrics operations must not lose their only dispatcher wake-up after the operation row commits.
- [x] Keep the explicit recovery sweep and manual reopen lifecycle. After Redis returns, pending database intents must re-enter only their handler-owned queue and converge through idempotent business state.
- [x] Add a read-only recovery snapshot that combines live Sidekiq availability/backlog with PostgreSQL intent counts, oldest pending age, dead letters, latest enqueue failure, and latest maintenance/manual recovery handoff.
- [x] When Redis is unavailable, the snapshot must still return the PostgreSQL recovery ledger without exception text, connection URLs, job arguments, source IDs, dedupe keys, or secrets.
- [x] Include the snapshot in the existing readiness payload and administrator jobs workspace. Readiness stays failed while the production Sidekiq dependency is unavailable; visibility must not mutate or trigger recovery.
- [x] Use stable Simplified Chinese and English copy from a new isolated locale file. Do not modify the concurrently edited shared locale catalogs.
- [x] Add focused test source for atomic rollback, Redis enqueue failure followed by ledger recovery, handler allowlisting, terminal-state convergence, degraded read fallback, privacy-safe recovery fields, health integration, and administrator props.

## Minimum state contract

```text
business transaction
  -> persist queued business row + allowlisted durable intent
  -> commit
  -> attempt Sidekiq handoff
       -> accepted: worker executes idempotently
       -> Redis unavailable: intent remains pending; user-visible row stays queued

Redis recovers
  -> existing one-minute recovery sweep reads pending PostgreSQL intents
  -> handler-owned Sidekiq handoff
  -> business row reaches its existing terminal state

durable-intent persistence unavailable
  -> roll back the business write
  -> stable background_processing_unavailable failure
```

The health and administrator snapshots are observations only. A successful recovery handoff means Redis accepted the durable dispatch job; it does not claim the underlying export or node operation completed.

## Deliberately deferred producer matrix

This minimum pass does not mechanically replace every direct enqueue. Payment webhook events, order webhooks, fulfillments, plugin deliveries, upload scans, mail notifications, and scheduled maintenance already have different combinations of durable source rows, reclaim jobs, idempotency, and user impact. Each requires a separate owner-aware migration rather than a generic arbitrary-job serializer. The follow-up audit must classify each path as durable-intent, source-row sweeper, safely best-effort, or fail-closed before changing it.

| Producer family | Current persistent recovery evidence | Follow-up classification |
| --- | --- | --- |
| Payment webhook receipt | Verified webhook event row plus the one-minute `RecoverWebhookEventsJob` reclaim path | Keep the source-row sweeper; later decide whether the initial handoff also benefits from the shared intent for uniform observability. |
| Order webhook delivery | Delivery rows, attempt state, and failed-delivery retry job | Source-row sweeper; do not duplicate payloads into the generic intent. |
| Order fulfillment and post-payment effects | Order/fulfillment state plus dedicated recovery jobs, but several direct chained enqueues remain | Audit each transition for a committed recovery predicate before migrating any wake-up. |
| Plugin lifecycle and outbound delivery | Plugin-owned persistent job/delivery stores and recovery jobs | Keep plugin payload ownership outside the core intent; add only an allowlisted wake-up if a lost-enqueue window remains. |
| Upload scan and cleanup | Upload/quarantine records and retry services exist, while several cleanup enqueues are best-effort | Separate security-required scans from garbage-collection cleanup; scans need durable recovery, cleanup may remain bounded best-effort. |
| General email delivery | Many domain records commit before a direct `MailDeliveryJob` enqueue | Migrate only mail that represents a security, payment, or irreversible lifecycle; ordinary informational mail may remain best-effort when an in-app persisted notification exists. |
| Scheduled maintenance | Sidekiq Cron re-registers schedules when the worker/Redis returns | Keep idempotent schedules; add missed-window reconciliation only for jobs whose source state cannot be rediscovered. |
| Delayed graceful server stop | Server state and connector tasks can be written before one delayed Sidekiq enqueue | High-priority follow-up: persist a handler-owned delayed intent or fail closed before changing lifecycle state. |

## Deferred verification

- Focused Rails tests for the new producers, recovery snapshot, readiness integration, and administrator props.
- Existing durable-enqueue, queue snapshot, node-operation, account export, finance export, and health suites.
- A production-like fault injection that stops Redis after the database commit, confirms truthful queued state and degraded readiness, restores Redis, and observes the existing sweep complete the same durable intent exactly once at the business layer.
- Browser inspection of the existing administrator jobs workspace in Simplified Chinese and English.
