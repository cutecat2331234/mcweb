# Settings namespace ownership

## Ownership decision

The namespace-ownership mechanism belongs to CE because every downstream
edition needs one fail-closed way to keep generic settings tools out of
configuration owned by a dedicated workflow. A downstream product registers
only its own namespace and continues to own its validation, locking,
versioning, publication, and rollback semantics.

EE-PVP will register `pvp.*`. CE must not contain PVP mode, queue, Tier, or
policy concepts.

## Task checklist

- [x] Add a process-wide, boot-time registry for owned setting prefixes.
- [x] Validate prefixes and owner identifiers and make duplicate registration
      idempotent while rejecting conflicting ownership.
- [x] Exclude owned keys from the generic System settings response.
- [x] Reject an entire generic update when any submitted key is owned.
- [x] Record a value-free audit event for each rejected request.
- [x] Keep ordinary, unowned settings behavior unchanged.
- [x] Add CE registry and controller regression coverage.
- [ ] Merge CE history through EE into EE-PVP.
- [ ] Register `pvp.*` in EE-PVP and prove the generic route cannot read or
      write those keys.

## Functional requirements

### Registration contract

1. A namespace is a lowercase dotted prefix ending in `.`.
2. An owner is a stable lowercase identifier suitable for audit metadata.
3. Registering the same prefix and owner more than once is safe.
4. Registering the same prefix for a different owner fails during boot.
5. The longest matching prefix identifies the owner, allowing a product to
   delegate a narrower namespace later without weakening a broader guard.

### Generic settings contract

1. Owned keys are not serialized to the generic settings page, including
   sensitive values that are already redacted.
2. A request containing one or more owned keys is rejected before any feature
   flag or ordinary setting is changed; mixed requests are atomic.
3. The rejection audit contains only sorted key names and owner identifiers,
   never submitted values or secrets.
4. The administrator receives localized guidance to use the owning product's
   dedicated configuration workflow.
5. Dedicated product services continue to write through their existing
   transaction, lock, reason, version, digest, and audit contracts.

## Acceptance checklist

- An unowned setting remains visible and writable through System settings.
- An owned setting is absent from System settings props.
- A direct PATCH for an owned key leaves every submitted key unchanged.
- A mixed owned/unowned PATCH is rejected without partial writes.
- The rejection creates exactly one audit event with no submitted value.
- Duplicate registration is idempotent; conflicting registration raises.
- EE-PVP protects `pvp.*` while its dedicated PVP configuration actions remain
  functional.

## Non-goals

- This registry does not implement a product's policy versions or migrations.
- It does not grant permissions or make hidden settings safe to expose.
- It does not allow a player or generic administrator to choose PVP testing
  modes; that remains server-owned PVP configuration.
