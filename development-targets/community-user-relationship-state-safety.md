# Community user relationship state safety

## Ownership

- **Owner:** CE.
- **Reason:** block, ignore, and follow are shared community and public API primitives inherited by every downstream edition.
- **Inheritance:** downstream editions consume this CE contract through the normal `CE -> EE -> EE-PVP` history; they must not recreate relationship writers.

## Problem

The former single `POST` toggle contract could reverse a user's intended state when a request was retried, delivered twice, or completed after the client timed out. Concurrent first writes could also race on the unique pair and expose a server error. This is especially unsafe for block and ignore because an accidental second toggle can remove a protection.

## Functional requirements

- Establish and remove are separate, explicit commands:
  - `PUT` means the relationship must exist.
  - `DELETE` means the relationship must not exist.
- A repeated command is idempotent and returns the same final state without creating duplicates or reversing the relationship.
- The shared writer fails closed when no explicit target state is supplied.
- Writes for the same two users are serialized in a stable lock order, while the database unique pair index remains the final concurrency boundary.
- A transient uniqueness race is absorbed or returned as a controlled conflict; it must not escape as an unhandled error.
- Responses expose the authoritative final state and whether this request changed it.
- Follow notifications are emitted only when follow changes from absent to present.
- Web controls suppress overlapping clicks and reconcile from the server response instead of applying an irreversible local toggle.
- The public API follows the same `PUT` / `DELETE` contract and returns `following` plus `changed`.
- Legacy relationship `POST` routes and toggle service entry points remain unavailable.

## Delivery checklist

- [x] Replace web block, ignore, and follow toggle routes with explicit `PUT` and `DELETE` routes.
- [x] Replace toggle services with `SetUserBlock`, `SetUserIgnore`, and `SetUserFollow`.
- [x] Centralize idempotent persistence in `SetUserRelationship`.
- [x] Serialize pair mutations through `Identity::UserMutationLock` and retain unique database indexes.
- [x] Return authoritative `blocked`, `ignored`, or `following` state together with `changed`.
- [x] Align the public follow API with explicit final-state semantics.
- [x] Disable duplicate profile, hover-card, and relationship-list actions while a request is active.
- [x] Reconcile Inertia surfaces from the server-rendered response and reload hover-card state after success.
- [x] Keep follow notification side effects transition-only.
- [ ] Run service, integration, JavaScript, and full edition verification in the centralized CNB pipeline.
- [ ] Perform final relationship-control visual acceptance in the local Edge session.

## CNB acceptance cases

- Repeated establish requests produce one row and report an active final state.
- Repeated remove requests produce no row and report an inactive final state.
- Timeout retry of the same explicit command never reverses the requested state.
- Concurrent establishes converge on one row without an unhandled exception or duplicate follow notification.
- Concurrent removals converge on no row.
- Missing desired state fails without changing data.
- Legacy `POST` endpoints cannot mutate block, ignore, or follow.
- API and Inertia callers observe the server's final state after each command.
- Profile, hover-card, block list, ignore list, and following list prevent overlapping user actions.
