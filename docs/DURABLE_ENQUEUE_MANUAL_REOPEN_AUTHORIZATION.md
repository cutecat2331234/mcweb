# Durable enqueue manual-reopen authorization

## Owner and scope

CE owns this change because handler-specific manual-reopen authorization is a
shared durable-enqueue contract. Downstream editions may declare a narrower
permission for their registered handlers, but must not copy authorization into
their own recovery service.

The existing `system.jobs.manage` requirement remains the default for every
handler that does not opt into a different permission. This change does not add
a global operations UI and does not define any PVP, chat, email, or commerce
semantics.

## Tasks

- [ ] Add a validated `manual_reopen_permission` field to registry entries.
- [ ] Default registrations to `system.jobs.manage` for compatibility.
- [ ] Resolve all explicitly selected intents to registered handlers before
  opening any ledger transaction.
- [ ] Reject unknown selections and unauthorized selections without partial
  mutation, audit, or enqueue side effects.
- [ ] Recheck authorization while each selected intent is locked before writing
  the `reopened` event.
- [ ] Cover registry validation, default compatibility, custom permission,
  mixed-selection atomic rejection, and successful custom-permission reopen.
- [ ] Run focused database tests, RuboCop, and Zeitwerk.

## Contract

`Operations::DurableEnqueueRegistry#register` accepts an optional
`manual_reopen_permission`. The value must be a canonical permission key. Its
default is `system.jobs.manage`.

`Operations::RecoverDurableEnqueue` keeps the existing manual actor, reason,
selection-size, and public-ID requirements. For `reopen: true`, it additionally:

1. requires every selected public ID to resolve to an existing intent;
2. requires every selected handler to remain registered;
3. requires the actor to hold the permission declared by each selected handler;
4. performs these checks for the complete selection before reopening any item;
5. rechecks the selected handler permission under the intent lock.

The service uses stable, non-sensitive failure codes. Authorization failures do
not identify which selected handler failed and do not record an audit event.
Valid but non-reopenable intents remain safe skips, preserving the existing
idempotent recovery behavior.

## Acceptance criteria

- Existing global job operators can reopen handlers that use the default.
- A custom-permission operator can reopen only handlers declaring that exact
  permission without receiving `system.jobs.manage`.
- A custom-permission operator cannot reopen a default or differently scoped
  handler.
- A mixed authorized/unauthorized or known/unknown selection causes zero ledger
  writes, zero audits, and zero enqueues.
- Registry freeze and duplicate-handler behavior remain unchanged.
