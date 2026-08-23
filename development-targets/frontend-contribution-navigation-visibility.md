# Frontend contribution navigation visibility

## Ownership

- **Owner:** CE.
- **Why:** every downstream product contribution needs the same fail-closed way to hide a navigation destination when the server says the current user cannot enter it. EE and EE-PVP must consume this primitive instead of adding product permission logic to shared layouts.

## Requirements

1. A contribution may declare one optional `visibility_prop` on a navigation item.
2. The property is a dot-separated path in the current Inertia page props and must resolve to the boolean value `true`; missing, deferred, failed, or non-boolean values hide the item.
3. `requires_authentication` remains an independent prerequisite.
4. The manifest, Ruby registry, generated TypeScript registry, executable adapter, and application shell must agree on the exact property path.
5. Portal, Staff, and Admin shells apply the same helper. The property controls discoverability only; controllers and policies remain authoritative.
6. Downstream products aggregate their own permission/module/workspace rules into a server-owned boolean prop. CE does not learn PVP or Channel concepts.

## Tasks

- [x] Extend the manifest schema and both registry parsers.
- [x] Include the field in adapter equality validation.
- [x] Add a fail-closed shared visibility resolver.
- [x] Apply it to Portal, Staff, and Admin contribution navigation.
- [x] Add a static contract for the complete wiring.
- [ ] Exercise the contract with EE Channel and EE-PVP contributions after their ordinary inheritance merges.

## Acceptance

- A contribution item without `visibility_prop` preserves current behavior.
- A protected item appears only when authentication requirements pass and its own page prop is exactly `true`.
- Missing or malformed visibility state never exposes the item.
- Direct forged requests are still denied by the existing server authorization layer.
