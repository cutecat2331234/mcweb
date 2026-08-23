# Minecraft player access rules

## Ownership

- Owner: CE.
- Reason: server access control, connector task delivery, permissions, and audit are shared Minecraft platform primitives used by every edition.
- Downstream editions consume the model and service through ordinary `CE -> EE -> EE-PVP` merges. PVP sanctions remain a separate product workflow and may call this primitive only through an explicit adapter.

## Product problem

Administrators can view online players and queue a kick, but whitelist, ban, and pardon operations otherwise require an unrestricted console command. That path has no dedicated state, expiry, retry identity, searchable history, or user-safe validation. A production server needs a bounded management workflow whose intent survives page refreshes and whose delivery result can be reconciled with the connector task.

## Functional requirements

- [x] Persist one immutable access-rule lifecycle per whitelist or ban decision, including server, player name/UUID, reason, actor, expiry, delivery tasks, timestamps, and optimistic version.
- [x] Expose dedicated create and revoke operations; never accept a raw command from the access-rule controller or browser.
- [x] Construct only fixed `whitelist add/remove` and `ban/pardon` commands after strict Minecraft username and reason validation.
- [x] Require an explicit idempotency key for apply and revoke, serialize mutations per server/target/rule type, and retain a database uniqueness boundary for active rules.
- [x] Fail closed when the Connector is offline or cannot accept `run_commands`; retain a visible failed record instead of claiming the rule is active.
- [x] Reconcile queued, completed, and failed Connector deliveries into the authoritative rule status without rewriting task results.
- [x] Allow an optional future expiry and queue a fixed revoke operation from a maintenance job.
- [x] Provide a dedicated Arco-based admin page with server/target/type/reason/expiry form, status history, explicit revoke confirmation, stable cursor paging, and links back to the player workspace.
- [x] Use the existing `minecraft.servers.control` capability and record apply, revoke, delivery, failure, and expiry events in the central audit log.
- [x] Keep all UI text in a dedicated bilingual Rails locale domain and avoid new custom CSS.
- [x] Add focused service/controller/model/task reconciliation test source.
- [ ] Run migrations and focused/full suites in CNB.
- [ ] Exercise apply, retry, failure, revoke, expiry, desktop, mobile, and bilingual flows in production-equivalent Connector infrastructure and local Edge.

## State machine

`pending_apply -> active -> pending_revoke -> revoked`

- A failed apply becomes `failed`; a failed revoke returns the rule to `active` so access is never falsely reported as removed.
- Repeating the same apply or revoke idempotency key returns the same rule and never queues another command.
- A new apply while an equivalent rule is already pending or active is a no-op only when its requested reason and expiry match; conflicting intent is rejected.
- Expiry is a normal audited revoke with a deterministic idempotency key. It never directly mutates the rule to revoked before the Connector confirms the fixed removal command.

## Security boundaries

- Target names must match the Java username alphabet and length. UUID is metadata only and never interpolated into commands.
- Reasons reject control characters and are bounded before command construction.
- The browser cannot choose the command, task type, delivery ID, status, actor, or server database ID.
- Connector request/response bodies and command output are not exposed on the rule page.
- Server capability/offline failure is reported as a stable public error; internal Connector details remain in task/audit storage.

## Deferred verification

No local test, build, typecheck, lint, syntax check, browser session, or CNB run is performed while authoring this feature. All code validation is deferred to the centralized CNB pass, followed by final Edge visual acceptance.
