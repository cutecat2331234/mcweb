# McWeb repository development rules

## Decide ownership before implementation

Every change must be assigned to the highest reusable product layer before code is written:

| Layer | Owns |
| --- | --- |
| CE | Shared platform capabilities, public contracts, node protocols, generic jobs, security fixes, and defects that affect every edition. |
| EE | Enterprise capabilities that build on CE but are not specific to one downstream product. |
| EE-PVP | PVP-only workflows, Tier rules, testing queues, rankings, and product-specific presentation. |

The development plan must state the selected owner and why. A downstream repository may consume an upstream capability, but must not copy or independently reimplement it.

If work in EE or EE-PVP exposes a reusable defect or missing primitive, pause the downstream implementation and fix it in the highest applicable upstream repository first. Verify and commit it there, then merge the same Git history down through `CE -> EE -> EE-PVP`. Keep downstream adapters in separate downstream commits.

Do not move product-specific concepts upstream merely to share code. Extract only the genuinely generic primitive; for example, Sidekiq-owned node operation groups belong to CE, while PVP test, Tier, and match semantics belong to EE-PVP.

## Inheritance and integration

- The only supported inheritance direction is `CE -> EE -> EE-PVP`.
- Preserve upstream commits with ordinary Git merges. Do not copy patches, cherry-pick, squash, rebase, or recreate an upstream change in a downstream repository.
- Never merge EE or EE-PVP history back into CE. Never merge EE-PVP history back into EE.
- Before a downstream merge, confirm the upstream worktree is clean, the change is committed, and its focused tests pass.
- If a downstream worktree has unrelated or uncommitted work, do not overwrite it. Checkpoint that work or defer the merge.
- Verify each layer after merging because downstream integrations can expose edition-specific failures.
