# Website content revision and recovery lifecycle

## Ownership

- Owner: CE.
- Reason: CMS revision integrity, recoverable deletion, publication safety, and administrator audit are shared website-platform capabilities. EE and EE-PVP inherit the same lifecycle through ordinary `CE -> EE -> EE-PVP` merges.
- Application owner: Admin owns editing, revision history, recycle-bin, restore, and purge pages. The public Website application owns published rendering only. Preview must cross that boundary with a native document navigation and must never make the Website resolver load Admin pages.

## Product problem

Pages currently keep only a limited post-change revision history and delete that history when the page is destroyed. Articles have no revision history at all, and both page and article deletion permanently remove the record. A mistaken edit, publication, schedule, or deletion can therefore destroy the last known-good public content and its audit evidence. The CMS entry also needs an explicit end-to-end acceptance contract because the administrator Website pages have been reported as unreachable in the browser.

## Functional requirements

### Unified immutable revisions

- Pages and articles use one CE-owned revision contract, while retaining type-specific snapshots.
- Record a complete immutable snapshot before every meaningful update, publish, schedule, archive, discard, and restore transition. A failed mutation must not leave an orphan revision.
- Page snapshots include metadata, translations, SEO, theme, publication fields, and an ordered copy of all blocks. Article snapshots include metadata, translations, SEO, summary, body, and publication fields.
- Existing revisions survive discard and restore. Revision rows must not be edited or cascade-deleted with their content record.
- Revision numbering is concurrency-safe and monotonically increasing per content record.
- Restoring an old revision creates a new draft state and a new audit/revision event; it never rewrites historical snapshots.

### Recoverable discard

- The ordinary Delete action becomes an explicit discard action and never performs a hard delete.
- Discard records `discarded_at`, `discarded_by`, a bounded reason, `purge_at`, and an optimistic `lock_version` transition.
- Public queries, navigation, sitemap/home resolution, scheduled publication, previews without Admin authorization, and ordinary Admin listings exclude discarded content.
- Discard is idempotent, audited, and safe under duplicate, delayed, concurrent, and out-of-order requests.
- Discarding a published home page fails closed until another valid home page is selected, or an explicit authorized replacement is part of the same transaction.

### Recycle bin and restore

- Admin provides separate recycle-bin index and detail views for pages and articles, with type, title, slug, discard actor/time/reason, purge deadline, and blocking conflicts.
- A permitted administrator can restore a discarded record after a confirmation that includes the target title and the consequences.
- Restore requires an explicit reason and current lock version, is idempotent, and restores content as a draft rather than publishing it automatically.
- Slug conflicts, home-page conflicts, missing themes, invalid block types, and navigation conflicts are detected before mutation and returned as stable localized errors. Restore must not silently rename content.
- Navigation and website caches converge after discard and restore; stale public URLs never render discarded content.

### Controlled final purge

- Final purge is a separate action and permission from edit/discard/restore.
- Purge is allowed only after the configured retention deadline and only when no legal hold, active navigation reference, scheduled job, or other protected reference blocks it.
- Purge requires step-up authorization when available, an exact-content confirmation, a bounded reason, lock version, and an idempotency key.
- Purge deletes mutable content and blocks while retaining a minimal tombstone, immutable revision snapshots, and audit records according to retention policy.
- Background retention cleanup uses the same purge service and authorization-independent safety checks; it must not bypass blockers.

### Interface and language requirements

- Use only shared `@mcweb/ui`/Arco components and existing design tokens.
- No gradients, moving cards, persistent focus decoration, handwritten selected borders, or development-target explanation text in the product UI.
- Keep list, detail, form, revision, and recycle-bin layouts consistent with the Admin design language on desktop and mobile.
- Keyboard order, labelled controls, error association, destructive-action confirmation, and live mutation feedback must remain accessible.
- All CMS user text belongs to the Admin Website locale domain in Simplified Chinese and English.

## State contracts

- Active content: `draft | scheduled | published | archived` with `discarded_at = null`.
- Discarded content: original publication state retained in revision history, `discarded_at != null`, unavailable to public and normal Admin queries.
- Restore: `discarded -> draft`; never `discarded -> published`.
- Purge: `discarded -> purged tombstone`, only after retention and blocker checks.
- Terminal purge cannot be reversed through application routes.

## Implementation task list

- [ ] Add durable revision support for articles and strengthen page revision retention, snapshot completeness, immutability, and concurrent numbering.
- [ ] Add discard metadata, tombstones, indexes, database constraints, and public/default active scopes for pages and articles.
- [ ] Add CE services for snapshot-backed update, publish/schedule, discard, restore, and final purge with locking, idempotency, audit, cache invalidation, and stable errors.
- [ ] Replace controller hard deletes and unsafe direct updates with the lifecycle services.
- [ ] Add Admin recycle-bin, revision history/detail, restore, and purge routes/controllers/serializers for pages and articles.
- [ ] Add Arco Admin interfaces and bilingual Admin Website language keys without custom visual primitives.
- [ ] Ensure public rendering, homepage selection, navigation, scheduling jobs, preview, direct links, and cache invalidation respect discard state.
- [ ] Add a dedicated CMS route/entry smoke contract so every Website Admin navigation target resolves and opens through the Admin application.
- [ ] Cover update snapshots, ordered page blocks, article body history, failed mutation atomicity, concurrency, discard/restore retries, slug/home/navigation conflicts, cache convergence, retention blockers, and irreversible purge.
- [ ] Merge committed CE history normally into EE and then EE-PVP.
- [ ] Run lightweight syntax/static/i18n checks locally; defer migration, database, build, Edge, desktop/mobile, and accessibility acceptance to the cached CNB batch after development completes.

## Acceptance matrix

- Reachability: every Admin Website menu link, direct link, refresh, and back/forward action opens the intended page without resolver or asset errors.
- History: pre-change page/article content and ordered blocks are recoverable after update, publication, scheduling, and discard; historical rows cannot be mutated through models or SQL constraints.
- Isolation: discarded records disappear from public URLs, homepage, navigation, sitemap, scheduled publication, and ordinary Admin lists, while remaining visible only in the authorized recycle bin.
- Restore safety: duplicate/concurrent restore converges once; slug, home, theme, block, and navigation conflicts fail without partial changes.
- Purge safety: early, unauthorized, held, referenced, replayed, or stale-version purge attempts fail closed; successful purge retains the required tombstone, revision, and audit evidence.
- Experience: Simplified Chinese, English, theme, keyboard, mobile layout, destructive confirmation, and cross-application preview navigation remain correct.
