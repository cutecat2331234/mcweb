# Community relationship active-write compatibility

## Ownership

- **Owner:** CE.
- **Reason:** block, ignore, and follow use one shared community persistence primitive in every edition.
- **Inheritance:** EE and EE-PVP must receive this repair only through ordinary `CE -> EE -> EE-PVP` merges.

## Problem

The explicit `PUT` / `DELETE` relationship contract is already in place, but the active-state writer calls Active Record 8.1.3.1 `create_or_find_by!` without its required attributes argument. Establishing a block, ignore, or follow therefore raises `ArgumentError` before it can converge on the requested state. Removal remains unaffected.

## Functional requirements

- Establish block, ignore, and follow relationships through the already-scoped relation without duplicating participant attributes.
- Supply the required attributes argument explicitly so the implementation remains compatible with the locked Active Record API.
- Preserve the existing user-pair lock, unique-index boundary, bounded conflict retry, final-state response, and transition-only follow notification.
- Keep retries and duplicate requests idempotent; this repair must not reintroduce toggle behavior.
- Align focused race-test doubles with the real Active Record method signature so the CNB suite exercises the production call shape.

## Delivery checklist

- [x] Confirm the locked Active Record signature requires an attributes argument.
- [x] Pass an explicit empty attributes hash to the scoped `create_or_find_by!` call.
- [x] Update focused conflict/retry source coverage to accept and forward that argument.
- [ ] Run relationship service, integration, JavaScript, and full-edition verification in CNB.
- [ ] Confirm establish/remove controls in the final local Edge acceptance pass.

## CNB acceptance cases

- Establishing each relationship from an absent state succeeds and creates exactly one row.
- Repeating the same establish request succeeds without another row or notification.
- A transient unique conflict retries with the same call shape and converges.
- An exhausted unique conflict returns the existing controlled conflict result instead of raising.
- Explicit removal remains idempotent and never recreates a relationship.
