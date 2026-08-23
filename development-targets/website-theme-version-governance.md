# Website Theme version governance

## Ownership

- Owner: CE.
- Reason: Website CMS Theme persistence, activation, revision history, safe recovery, and audit are shared platform capabilities. EE and EE-PVP must inherit the committed CE history through ordinary `CE -> EE -> EE-PVP` merges.
- Downstream boundary: edition-specific Theme presentation may remain downstream, but it must consume this CE lifecycle rather than copying revision or restore logic.

## Production problem

Website Themes are currently overwritten in place. Creation, editing, and activation leave no immutable version history, while activation updates every Theme without optimistic concurrency or an attributable audit trail. An administrator therefore cannot inspect what changed, identify the version that supplied a known-good site appearance, or safely converge a retried recovery request.

## Functional requirements

### Immutable revisions

- Every administrator create, edit, and activate action appends an immutable Theme revision in the same transaction as the Theme mutation.
- Creation records an explicit initial baseline. Edit, activate, deactivate, and restore services record the whitelisted pre-change snapshot before mutating the Theme, so recovery never depends on a model after-save callback.
- A revision has a monotonically increasing per-Theme number, a whitelisted snapshot, event type, actor, reason when applicable, source Theme lock version, and creation time.
- Existing revision rows cannot be updated or deleted through the model or database.
- Restoring an old revision never rewrites it. The restored Theme state is captured in a new successor revision that identifies the source revision.
- Existing Themes receive one legacy baseline revision during migration without inventing an actor.
- Revisions retain a database foreign key to their Theme. A Theme with immutable history cannot be hard-deleted, so history never becomes an unreachable orphan.

### History and comparison

- Theme detail exposes a history entry to administrators with `website.pages.read`.
- History is server-paginated in deterministic `revision_number DESC, id DESC` order and redirects out-of-range pages to the canonical last page.
- Revision detail exposes only the Theme fields required for review: name, key, activation state, and Theme tokens.
- Difference output compares the selected revision with its immediate predecessor and returns only changed whitelisted paths and values. Request digests, internal operation digests, database details, and unrelated user data are never serialized.

### Safe recovery

- Recovery requires both `website.pages.edit` and `website.content.restore`.
- The administrator must provide a bounded reason, confirm the exact target revision number, submit the current Theme `lock_version`, and provide an idempotency key.
- The service locks the Theme, verifies the revision belongs to it, rejects stale versions, and applies only the whitelisted snapshot.
- Recovery preserves the Theme's current activation state so version recovery cannot implicitly change the live Theme selection. Activation remains an explicit separately authorized action.
- An identical retry returns the existing successful result. Reusing the key with a different Theme, target revision, reason, confirmation, or source version fails closed.
- Concurrent attempts converge through row locking, optimistic version checks, and database uniqueness constraints.

### Audit and interface

- Recovery audit records actor, bounded reason, source revision number, submitted current version, resulting current version, and the successor revision number.
- Create, edit, and activation audits contain whitelisted before/after state only; Theme tokens are represented by changed paths or counts rather than unrelated request data.
- UI uses existing Admin layout and Arco controls only. No custom CSS, animation, or visual embellishment is added.
- All new interface and stable error text lives in dedicated English and Simplified Chinese locale files.

## Implementation task list

- [x] Add `lock_version` to Themes and create the immutable revision table, constraints, indexes, trigger, and legacy baseline backfill.
- [x] Add Theme revision associations, snapshot/difference helpers, lifecycle error handling, and transactional create/edit/activate/restore services.
- [x] Replace direct Admin Theme writes with the CE lifecycle services while preserving existing permissions.
- [x] Add nested Theme revision index, show, and restore routes without changing unrelated routing hunks.
- [x] Add deterministic server pagination and minimized serializers for history and difference detail.
- [x] Add Arco-only Theme history and revision detail/recovery screens plus links from Theme detail.
- [x] Add dedicated English and Simplified Chinese locale files.
- [x] Add source tests for revision creation, immutability, deterministic pagination, minimized serialization, authorization, stale versions, idempotency replay/reuse, concurrent restore convergence, successor history, deletion safety, and audit content.
- [x] Leave tests, builds, static checks, browser acceptance, and CNB untouched for the parent validation batch.

## Acceptance contract

- Creating a Theme records its initial baseline. Editing or activating records exactly one pre-change revision for the requested Theme mutation; failed mutations leave neither revision nor audit residue.
- A history with more than one page has stable order and stable canonical pagination.
- Revision detail reports the immediate predecessor difference without exposing internal idempotency or audit storage fields.
- A permitted administrator can restore a prior content version only after exact confirmation and with the current lock version.
- Duplicate identical restore requests converge on one successor revision and one audit; a conflicting replay or stale concurrent request mutates nothing.
- Restore retains current live/inactive status and never changes another Theme's activation state.
- Old and source revision rows remain unchanged after successful recovery.
- A Theme with revision history cannot be hard-deleted, and every retained revision remains reachable through its parent Theme.
