# Minecraft world restore production safety lifecycle

## Ownership and coordination boundary

- Owner: CE.
- Reason: managed backups, the node protocol, destructive-operation authorization, filesystem safety, crash recovery, and audit are reusable platform primitives for every McWeb edition. EE and EE-PVP may consume the committed CE history only through ordinary CE -> EE -> EE-PVP merges.
- Product boundary: this work contains no PVP, Tier, testing-queue, or EE-only concepts.
- UI boundary: the Admin surface uses the existing AdminLayout, Arco Design Vue, and the @mcweb/ui seam. It does not introduce another component kit or apply the EE-PVP public Astro exception.
- Coordination boundary for the 2026-08-23 first pass: inspect existing files read-only and create only this document. Do not implement or commit until the active report/appeal work has left the CE tree clean.

## Current unsafe baseline

The current CE implementation is not a production-safe restore lifecycle:

- Admin accepts a caller-supplied archive filesystem path and enqueues a legacy restore_world node task.
- The node shells out to tar and extracts directly into the configured world target without a stopped-process check, manifest binding, archive-entry policy, staging verification, rollback ledger, or atomic cutover.
- Manual and scheduled backup jobs create caller/configuration-derived destination paths and do not create managed backup records or integrity manifests.
- Legacy backup_world and restore_world are v1 node tasks. The durable v2 operation protocol currently advertises and accepts only collect_metrics and sync_files.
- Rails has a process_state projection and the node can query the real process driver. The real node driver result must be authoritative for restore safety.
- The v2 node operation store already blocks other node work while an operation is unacknowledged. Restore will build on that delivery contract but needs its own phase ledger because a crash can happen inside one filesystem target.
- Identity::SensitiveActionVerifier and the Admin high-risk action pattern already provide password plus TOTP/recovery-code step-up semantics. Restore must reuse that identity primitive, not invent weaker authentication.

## Non-negotiable safety invariants

1. Admin and Rails never accept an archive path for restore. A restore target is selected only by an opaque managed backup public ID.
2. A managed backup is restorable only when its immutable node-side manifest and Rails-bound manifest digest agree.
3. Restore is v2-only. The control plane requires protocol version 2, both explicit world operation types, and the complete safety capability profile. Missing, stale, malformed, or partially advertised capability data fails closed.
4. Only one active restore plan may exist per server. A server with an active or recovery-required restore cannot start, restart, move nodes, change its world/working directory, or begin another restore.
5. Planning, authorization, enqueueing, node execution, crash recovery, and cutover each re-evaluate their own prerequisites. A successful earlier check is not treated as proof of current state.
6. The database process_state must be stopped before plan, authorization, and enqueue. The node must independently query the configured process driver and receive the exact stopped state before snapshot, before archive extraction, immediately before cutover, and whenever a crashed restore resumes. Unknown, error, starting, stopping, or running all fail closed.
7. Restore never stops or starts the server automatically. The operator stops it separately, and it remains stopped after success, safe rollback, or failure.
8. A durable pre-restore snapshot, or a durable explicit “world absent” marker, must exist before the live world is renamed.
9. No archive entry is written into the live world. The complete archive is validated, extracted, and verified in a new sibling staging directory on the same filesystem.
10. Cutover uses only same-filesystem directory renames. The live tree is never incrementally overwritten.
11. Every destructive phase transition is durable on the node before the next filesystem mutation. Rails also retains an append-only operational event ledger and the normal immutable audit log.
12. Duplicate HTTP requests, Sidekiq retries, node re-delivery, result re-delivery, and process restarts converge on one plan, one node operation, one pre-restore backup, and one final outcome.
13. Authorization tokens, passwords, TOTP/recovery codes, absolute paths, process configuration, and full node payloads are never returned in audit/UI data or written to logs.

## Managed backup contract

### Identity and storage

- Rails allocates the backup public ID before enqueueing node work.
- The node derives storage from local configuration, never from the operation payload:
  - world_backup_root/server_id/backup_id/world.tar.gz
  - world_backup_root/server_id/backup_id/manifest.json
- server_id and backup_id are validated as bounded opaque identifiers before path construction.
- The archive and manifest are created in a private sibling temporary directory, flushed, and renamed into the final backup-ID directory only after both are complete.
- A backup is usable only on the node that created it. Moving/copying a backup between nodes is a future explicit transfer protocol, not an implicit path feature.
- Existing unmanaged archives are left untouched but are not selectable or importable through this lifecycle.

### Manifest version 1

The node stores the full canonical manifest sidecar. Rails stores only the bounded public summary plus the SHA-256 digest of the canonical full manifest.

Required full-manifest fields:

- manifest_version
- safety_profile
- backup_id
- server_id
- node_id
- purpose: manual, scheduled, or pre_restore
- request_digest
- created_at in UTC
- archive_format: tar.gz
- archive_sha256
- archive_bytes
- uncompressed_bytes
- entry_count
- world_relative_path
- source_process_state: stopped, or source_world_state: absent
- entries sorted by canonical relative path
- for every directory: relative path and kind
- for every regular file: relative path, byte size, and SHA-256

The manifest digest binds the complete ordered entry list. A restore recomputes the archive digest, manifest digest, entry set, file sizes, and per-file digests. A summary-only match is insufficient.

### Backup lifecycle

- requested -> queued -> creating -> available
- requested/queued/creating -> failed
- available -> quarantined when later verification detects loss or mismatch
- Records are never marked available until the acknowledged v2 result has passed Rails result validation.
- Scheduled and manual backups use the same service and v2 node operation.
- Until a future explicit online-snapshot capability exists, managed backups require the real process driver to report stopped. Scheduled occurrences while running record a stable skipped/failed reason rather than creating a possibly inconsistent archive.
- No automatic backup deletion or legacy-archive deletion is introduced in this change.

## Rails data model

### minecraft_world_backups / Minecraft::WorldBackup

Core columns and constraints:

- public_id, unique and immutable
- minecraft_server_id and minecraft_node_id, required
- minecraft_node_operation_id, optional until queued and unique when present
- created_by_id, optional for scheduled/system backups
- purpose enum: manual, scheduled, pre_restore
- status enum: requested, queued, creating, available, failed, quarantined
- request_id and request_digest for idempotency; the same request ID with a different digest is a conflict
- manifest_version, safety_profile, archive_format
- manifest_digest and archive_sha256, lower-case 64-character SHA-256 values
- archive_bytes, uncompressed_bytes, entry_count with non-negative database checks
- manifest_summary, bounded JSON only
- verified_at, failed_at, error_code, timestamps, and lock_version
- unique indexes for public_id, request_id, and node operation

The model rejects mutation of identity, source, and manifest fields after available. Status transitions occur only through lifecycle services.

### minecraft_world_restore_plans / Minecraft::WorldRestorePlan

Core columns and constraints:

- public_id, unique and immutable
- minecraft_server_id, minecraft_node_id, and minecraft_world_backup_id, required
- pre_restore_world_backup_id and minecraft_node_operation_id, optional until execution
- actor_id, required
- status enum: planned, authorized, queued, running, completed, failed, rolled_back, recovery_required, expired, cancelled
- reason, required and bounded
- request_id and request_digest, unique/idempotent
- plan_digest, immutable SHA-256 of the frozen plan
- backup_manifest_digest
- server_configuration_digest and node_capability_digest
- frozen server updated_at value and relative world directory
- authorization_digest, authorization_method, authorization_expires_at, authorized_at, and authorization_consumed_at
- queued_at, started_at, completed_at, failed_at, error_code
- result_summary, bounded JSON; never absolute paths or credentials
- timestamps and lock_version
- a partial unique index allowing only one planned/authorized/queued/running/recovery_required plan per server

The frozen plan digest covers actor, server, node, backup, backup manifest, reason, relative world directory, server configuration, node capability profile, and request ID. Lifecycle columns may advance under a row lock; frozen plan fields may not change.

### minecraft_world_restore_events / Minecraft::WorldRestoreEvent

- minecraft_world_restore_plan_id, required
- sequence, monotonically increasing per plan
- event_type and phase, required
- actor_id, optional for node/system events
- payload_summary, bounded and sanitized
- payload_digest
- created_at only
- unique plan/sequence index
- model- and database-level append-only behavior

The event ledger records plan, authorization, enqueue, node start, pre-snapshot, validation, staging, cutover, verification, rollback, recovery-required, completion, and acknowledgement outcomes. AuditLog remains the cross-domain administrative record; the restore event table is the detailed operational ledger.

## Plan -> step-up authorize -> execute

### 1. Plan

- Requires minecraft.world_restores.execute.
- Input is server ID, available managed backup ID, bounded reason, and UUID request ID.
- The service locks/reloads the server and validates:
  - server is node-managed and process_state is stopped
  - node heartbeat is fresh
  - node and backup belong to the same server/node
  - backup is available with a complete supported manifest summary/digest
  - exact v2 safety capability profile is present
  - relative world path and current server configuration pass policy
  - no other active restore exists
- It persists an immutable plan and returns only a sanitized preview, blockers, typed-confirmation text, plan ID, digest suffix, and expiry.
- Repeating the same request ID and digest returns the same plan. Reusing the request ID with changed input fails.

### 2. Step-up authorize

- Requires the same permission and ownership of the plan action.
- Rechecks plan expiry, server/node/backup identity, stopped state, configuration digest, capability digest, and active-plan uniqueness.
- Uses Identity::SensitiveActionVerifier with the current password and, when enabled, TOTP or a consumed recovery code.
- Issues a five-minute signed token bound to actor ID, plan ID, plan digest, plan lock version, reason digest, server state/configuration digest, backup manifest digest, authorization method, and a random nonce.
- Persists only the token digest and method. The response is Cache-Control: no-store.
- Typed confirmation names the exact server, backup, and plan suffix.

### 3. Execute

- Requires the same permission, exact confirmation, unexpired token, token digest match, and a still-current frozen plan.
- Under a plan row lock, consumes authorization once, preallocates the pre-restore backup ID, creates exactly one v2 node operation with the plan request ID, and advances authorized -> queued.
- Duplicate execution returns the same plan/operation. A mismatched replay fails.
- The v2 payload contains opaque IDs and frozen digests, not a backup path or caller-selected destination.
- The node performs its own independent checks and returns a bounded result summary. Rails reconciliation advances the plan and backup records exactly once by using the existing target-result applied_at guard.

## Node protocol v2 and capability fail-closed behavior

Heartbeat must advertise all of the following before Admin enables planning:

- node_protocol_versions contains 2
- operation_types contains world_backup_create and world_restore_execute
- operation_capabilities.world_backup_create declares protocol_version 2, manifest version 1, tar.gz, stopped_source_required, and managed_storage
- operation_capabilities.world_restore_execute declares protocol_version 2, manifest version 1, safety profile mcweb-world-restore-v1, safe_extract, same_filesystem_atomic_swap, pre_restore_snapshot, durable_ledger, crash_recovery, and rollback

Rails accepts exact known values only. A boolean “supports restore” flag, an unknown newer profile, or an operation type without the structured capability is not enough.

### world_backup_create target payload

- protocol_version: 2
- backup_id
- server_id and node_id
- purpose
- request_digest
- world_relative_path
- working_directory, process_driver, and process_config from the frozen server record
- safety_profile: mcweb-world-restore-v1

There is no destination, archive path, shell command, or caller-provided limit.

### world_restore_execute target payload

- protocol_version: 2
- plan_id and plan_digest
- server_id and node_id
- backup_id and backup_manifest_digest
- pre_restore_backup_id
- world_relative_path
- frozen server configuration digest
- working_directory, process_driver, and process_config
- safety_profile: mcweb-world-restore-v1
- expected_process_state: stopped

The node uses its local backup root and local hard limits. The control plane may request a stricter known profile but cannot raise node limits.

### Bounded result payload

Backup results return backup ID, manifest/archive digests, summary counts/sizes, and final status.

Restore results return plan ID, installed manifest digest, pre-restore backup digest/summary, final node phase, rolled_back flag, recovery_required flag, stable error code, and timestamps. They never return absolute paths, archive entries, process configuration, or secret material.

## Safe archive validation and extraction

Only gzip-compressed POSIX tar created by the managed backup writer is supported. Zip, uncompressed tar, external tar variants, and caller-imported archives fail closed.

Validation happens before extraction and is repeated while streaming extraction:

- Verify managed ID lookup, sidecar manifest digest, archive SHA-256, compressed size, manifest version, safety profile, server/node identity, and expected entry ordering.
- Require valid UTF-8 relative POSIX paths. Reject empty paths, NUL/control characters, dot segments, traversal, leading slash, drive-letter roots, UNC/device/extended paths, and every backslash rather than translating it.
- Allow only regular files and directories. Reject symbolic links, hard links, character/block devices, FIFOs, sockets, unknown type flags, GNU/PAX sparse records, and sparse metadata.
- Reject duplicate canonical paths, file/directory prefix conflicts, case-fold collisions, and platform-equivalent collisions.
- Reject Windows alternate data streams and drive syntax by rejecting colon in every component.
- Reject trailing dots/spaces and reserved device names including CON, PRN, AUX, NUL, CLOCK$, CONIN$, CONOUT$, COM1-COM9, and LPT1-LPT9 even when an extension is present.
- Reject names that exceed the component/path byte limit or depth limit.
- Enforce node-local hard ceilings for compressed bytes, manifest bytes, total uncompressed bytes, per-file bytes, entry count, directory count, path depth, and expansion ratio.
- Count actual streamed bytes and reject truncation, extra archive entries, reordered/missing manifest entries, size mismatch, digest mismatch, trailing concatenated gzip members/data, and quota overrun.
- Preflight conservative free space for the pre-restore snapshot, staging tree, and rollback window.
- Ignore archive owner, group, ACL, xattr, timestamps, setuid/setgid/sticky bits, and executable bits. Create private directories/files with fixed safe modes.
- Use directory-relative, no-follow filesystem operations where supported and reject symlink/junction/reparse-point components in the configured working path and live world.

Initial node-local default ceilings are documented and tested; configuration may lower them. Suggested upper defaults are 64 GiB compressed, 256 GiB uncompressed, 64 GiB per file, 2,000,000 entries, depth 64, path length 1,024 bytes, and expansion ratio 200:1.

## Staging, atomic cutover, rollback, and recovery

### Staging

- Resolve and validate working_directory plus world_relative_path without following links.
- Create a unique private staging directory as a sibling of the live world, which guarantees the same parent filesystem.
- First scan/validate the complete archive without writing files.
- Reopen it, extract into staging through the safe writer, and verify the staged tree against every manifest entry and digest.
- Flush created files and directories before making staging eligible for cutover.

### Durable node ledger

The node stores one private ledger per plan below its spool-owned world-restores directory. Every update is written to a new file, flushed, atomically replaced, and followed by a parent-directory flush when supported. It binds plan ID, operation delivery ID, payload digest, server ID, all managed backup IDs/digests, and the frozen target configuration.

Durable phases:

- accepted
- process_stopped
- pre_snapshot_started
- pre_snapshot_durable
- archive_validated
- staging_started
- staging_verified
- live_preserved
- replacement_installed
- post_install_verified
- rollback_started
- rolled_back
- completed
- recovery_required

### Cutover

1. Re-query the process driver and require stopped.
2. Persist staging_verified.
3. Atomically rename the live world to a private sibling rollback directory and persist live_preserved.
4. Atomically rename staging to the exact live name and persist replacement_installed.
5. Verify the installed tree/digest and persist post_install_verified.
6. On success, retain the durable pre-restore managed backup, safely remove the redundant live-tree rollback directory, and persist completed.

Each rename is an atomic same-filesystem directory operation; the stopped server prevents observation of the short two-rename cutover window.

### Crash and failure recovery

- Before live_preserved: discard/rebuild staging and resume from the last durable safe phase.
- At live_preserved without replacement_installed: restore the preserved live directory before accepting other work.
- At replacement_installed: verify the new live tree. If it is complete, finish idempotently; otherwise begin rollback.
- Any validation or post-cutover failure automatically renames the failed replacement aside and restores the preserved live directory.
- A safely restored old tree yields rolled_back, not an ambiguous generic failure.
- If rollback cannot be proven complete, persist recovery_required, advertise the blocker in heartbeat metadata, reject server start/restart and further world operations, and surface a stable Admin remediation state.
- Re-delivery with the same plan/payload digest resumes or returns the durable result. The same plan ID with another digest is rejected.
- A later operator-requested rollback uses the pre-restore backup through a new plan and the same step-up lifecycle; there is no unaudited shortcut.

## Permissions and audit

New permissions:

- minecraft.world_backups.manage: request and inspect managed backups
- minecraft.world_restores.execute: plan, authorize, and execute restores

minecraft.servers.control remains responsible for ordinary start/stop/restart and cannot authorize restore. minecraft.servers.manage alone can view the server page but cannot reveal restore controls without the new permissions.

Audit actions include:

- minecraft.world_backup.requested
- minecraft.world_backup.available
- minecraft.world_backup.failed
- minecraft.world_backup.quarantined
- minecraft.world_restore.planned
- minecraft.world_restore.authorized
- minecraft.world_restore.queued
- minecraft.world_restore.started
- minecraft.world_restore.pre_snapshot_available
- minecraft.world_restore.completed
- minecraft.world_restore.failed
- minecraft.world_restore.rolled_back
- minecraft.world_restore.recovery_required
- minecraft.world_restore.expired

Audit metadata contains opaque public IDs, status/phase, reason, request ID, digest suffixes, counts/sizes, and stable error codes only. Step-up secrets, full digests where unnecessary, filesystem paths, archive entries, and process configuration are excluded.

## Admin UI and i18n contract

- Replace the raw archive-path input on the existing server detail page with one managed “World backup and restore” lifecycle panel.
- The panel uses existing Arco steps, alerts, descriptions, tables, tags, forms, password input, buttons, and Message service through the current Admin stack.
- Show managed backup ID, purpose, availability, creation/verification time, archive/uncompressed size, entry count, and short manifest digest. Never show the node path.
- Backup creation is a separate permission-gated action.
- Restore uses three visible steps: select/freeze plan -> password/TOTP step-up -> exact typed confirmation/execute.
- Disable planning with localized blockers for running/stale/unmanaged/incompatible nodes, unavailable backups, configuration changes, and an active/recovery-required restore.
- Show current plan/operation phase, pre-restore backup ID, rollback result, stable error, and an explicit refresh action.
- Maintain keyboard order, labels, validation association, no-store authorization handling, mobile single-column layout, and non-color-only statuses.
- All text belongs to the existing adminMinecraft locale domain in Simplified Chinese and English. Rails service/permission/audit labels live in the mcweb domain locale files.
- Do not modify Admin navigation or add a second top-level menu; the lifecycle remains owned by the existing server detail page.

## Legacy retirement and rollout order

1. Ship the new node first. It advertises v2 world capabilities only when managed storage and recovery initialization succeed. It rejects legacy restore_world and backup_world execution with stable retired-operation errors.
2. The control plane remains safe during the rolling gap: old Rails restore attempts are rejected by the new node; new Rails later refuses nodes lacking the exact v2 profile.
3. Replace manual and scheduled backup enqueueing with managed world_backup_create operations.
4. Remove backup_world and restore_world from EnqueueNodeTask and remove the Admin legacy endpoints/raw path input.
5. Mark any still-pending/claimed legacy backup_world or restore_world database tasks failed with a legacy-retired result while preserving completed history.
6. Stop accepting backup_directory updates. Existing metadata and existing disk archives are preserved but ignored; this change does not delete or silently import them.
7. Keep the existing scheduled_minecraft_backups cron entry and job class, so config/sidekiq_cron.yml does not need another concurrent edit.
8. Do not push. Commit only the owned CE files directly on main after the tree is clean. The parent integration may later merge the exact CE commit history downstream in order.

## Prospective implementation file ownership

### New CE Rails/Admin files

- db/migrate/20260823193000_create_minecraft_world_restore_lifecycle.rb
- app/models/minecraft/world_backup.rb
- app/models/minecraft/world_restore_plan.rb
- app/models/minecraft/world_restore_event.rb
- app/services/minecraft/world_path_policy.rb
- app/services/minecraft/world_backup_manifest.rb
- app/services/minecraft/create_world_backup.rb
- app/services/minecraft/plan_world_restore.rb
- app/services/minecraft/authorize_world_restore.rb
- app/services/minecraft/execute_world_restore.rb
- app/services/minecraft/append_world_restore_event.rb
- app/services/minecraft/reconcile_world_operation.rb
- app/controllers/admin/minecraft/world_backups_controller.rb
- app/controllers/admin/minecraft/world_restores_controller.rb
- app/javascript/components/admin/minecraft/WorldRestoreLifecycle.vue
- app/javascript/components/admin/minecraft/worldRestoreTypes.ts
- test/services/minecraft/world_restore_lifecycle_test.rb
- test/javascript/admin_minecraft_world_restore_ui_test.ts

### Existing CE Rails/Admin files expected to change

- app/controllers/admin/minecraft/servers_controller.rb
- app/javascript/pages/Admin/Minecraft/Servers/Show.vue
- app/jobs/minecraft/scheduled_backup_world_job.rb
- app/jobs/minecraft/reconcile_node_operation_job.rb
- app/models/minecraft/node.rb
- app/models/minecraft/node_operation.rb
- app/models/minecraft/server.rb
- app/services/minecraft/enqueue_node_operation.rb
- app/services/minecraft/enqueue_node_task.rb
- app/services/minecraft/node_operation_dispatcher.rb
- app/services/minecraft/record_node_heartbeat.rb
- app/services/identity/permission_catalog.rb
- config/routes.rb
- config/locales/mcweb.en.yml
- config/locales/mcweb.zh-CN.yml
- app/javascript/locales/en.ts
- app/javascript/locales/zh-CN.ts
- db/schema.rb
- test/services/minecraft_p2_features_test.rb
- NODE_PROTOCOL.md
- lib/mcweb/application_registry.rb

### New CE node files

- nodes/mcweb-node/internal/worldstore/types.go
- nodes/mcweb-node/internal/worldstore/policy.go
- nodes/mcweb-node/internal/worldstore/manifest.go
- nodes/mcweb-node/internal/worldstore/archive.go
- nodes/mcweb-node/internal/worldstore/store.go
- nodes/mcweb-node/internal/worldstore/ledger.go
- nodes/mcweb-node/internal/worldstore/restore.go
- nodes/mcweb-node/internal/worldstore/filesystem.go
- nodes/mcweb-node/internal/worldstore/filesystem_unix.go
- nodes/mcweb-node/internal/worldstore/filesystem_windows.go
- nodes/mcweb-node/internal/worldstore/policy_test.go
- nodes/mcweb-node/internal/worldstore/restore_test.go

### Existing CE node files expected to change

- nodes/mcweb-node/internal/agent/agent.go
- nodes/mcweb-node/internal/config/config.go
- nodes/mcweb-node/internal/config/config_test.go
- nodes/mcweb-node/config/mcweb-node.example.yml
- nodes/mcweb-node/internal/executor/executor.go
- nodes/mcweb-node/internal/operation/types.go
- nodes/mcweb-node/internal/operation/store_test.go
- nodes/mcweb-node/internal/drivers/script.go
- nodes/mcweb-node/internal/drivers/systemd.go
- nodes/mcweb-node/internal/drivers/docker.go
- nodes/mcweb-node/internal/drivers/nssm.go

No go.mod/go.sum change is planned unless implementation proves a standard-library-only portable collision policy impossible; adding a dependency requires an explicit plan update before staging.

## Known overlap with the active report/appeal tree

Read-only coordination snapshot at 2026-08-23 19:27 +08:00:

- Direct planned overlap with currently modified files:
  - config/routes.rb
  - db/schema.rb
  - app/javascript/locales/en.ts
  - app/javascript/locales/zh-CN.ts
  - config/locales/mcweb.en.yml
  - config/locales/mcweb.zh-CN.yml
- config/sidekiq_cron.yml is currently modified by report/appeal work, but this plan deliberately keeps the existing backup cron entry and does not claim that file.
- The active migration is db/migrate/20260823140000_add_community_report_appeals.rb. This plan reserves the distinct new filename db/migrate/20260823193000_create_minecraft_world_restore_lifecycle.rb.
- ArcoAdminLayout.vue, StaffLayout.vue, adminRoutes.ts, routes.ts, usePortalNav.ts, report controllers/models/services/pages, secure-evidence integration, and report-appeal jobs are active unrelated ownership and are explicitly outside this task.
- The Minecraft server controller/page, Minecraft lifecycle services/models/tests, node Go tree, permission catalog, and all listed new paths were clean at this snapshot.

Implementation must re-run status after the follow-up and stop again if any prospective owned existing file remains dirty or if the reserved migration filename has appeared.

## Phased implementation checklist

### Phase 0 — coordination and frozen design

- [x] Assign the highest reusable owner to CE and document why.
- [x] Inspect the current legacy backup/restore path, v2 operation protocol, process-state model, step-up verifier, audit service, Admin UI library, and dirty-tree overlaps without editing existing files.
- [x] Freeze data, manifest, protocol, archive, cutover, recovery, permission, audit, i18n, legacy, and rollout contracts in this document.
- [x] Receive explicit follow-up that the CE tree is clean.
- [x] Re-check main, status, prospective paths, and migration filename before any implementation.

### Phase 1 — schema and Rails domain invariants

- [x] Add backup, restore-plan, and immutable restore-event tables with foreign keys, checks, idempotency indexes, append-only guards, and one-active-restore-per-server enforcement.
- [x] Add models/associations and frozen-field/status-transition protections.
- [x] Add portable relative-world-path, manifest-summary, digest, request, capability, and state validators.
- [x] Add permissions and bilingual domain error/audit labels.

### Phase 2 — node managed storage and safety engine

- [x] Add node-local managed backup root/config defaults, fail capability advertisement when initialization is unavailable, and advertise an explicit recovery blocker for unresolved ledgers.
- [x] Add canonical manifest writer/reader and stopped-only managed backup creation.
- [x] Add the complete malicious archive validation matrix and two-pass extraction.
- [x] Add sibling staging, free-space preflight, durable pre-restore snapshot, same-filesystem rename cutover, verification, rollback, and phase-ledger recovery.
- [x] Add platform helpers for Unix and Windows no-follow/reparse, filesystem identity, durable rename, and directory sync behavior.
- [x] Add v2 operation types/results and dynamic structured capability advertisement.
- [x] Remove executable legacy archive restore/backup paths.

### Phase 3 — Rails orchestration and reconciliation

- [x] Implement idempotent managed backup creation for manual and scheduled callers.
- [x] Implement frozen plan, step-up authorization, one-time execute, and start/restart/configuration gating.
- [x] Enqueue exactly one v2 operation and preallocate exactly one pre-restore backup.
- [x] Reconcile node results once, including unreported operation failures, rollback, and recovery-required states.
- [x] Append sanitized restore events and AuditLog entries at every material transition.
- [x] Retire legacy routes/tasks and preserve old history/archives without importing or deleting them.

### Phase 4 — Admin UI and language

- [x] Replace raw archive-path restore with the managed lifecycle panel on the existing server detail page.
- [x] Add backup list/create, explicit blockers, three-step restore, typed confirmation, current phase, rollback/recovery state, and refresh.
- [x] Use only existing Arco/@mcweb/ui components and current Admin layout/tokens.
- [x] Add complete Simplified Chinese/English Admin Minecraft copy and Rails service/permission/audit copy.
- [x] Add focused static contracts for component use, no raw path field, step-up inputs, i18n parity, and route/permission coherence.

### Phase 5 — adversarial verification and CE commit

- [ ] Cover traversal, absolute/drive/UNC/device/backslash paths, links, devices, FIFO, sparse forms, duplicate/case/prefix collisions, ADS, reserved names, depth/path/count/size/ratio limits, truncation, trailing data, digest mismatch, and disk exhaustion.
- [ ] Inject crashes at every durable phase and prove old-or-new convergence, idempotent resume, safe rollback, and recovery-required blocking.
- [ ] Cover running/unknown/stale states, capability downgrade, node/server movement, backup quarantine, plan/token expiry, replay/conflict, concurrency, and start/restart races.
- [ ] Cover pre-restore snapshot success/failure and restoration from that managed backup through a new authorized plan.
- [x] Locally run only gofmt, Ruby syntax, static manual review, i18n parity inspection, and git diff checks; all test execution, typechecks, and builds remain CNB-only.
- [ ] Use CNB for the focused Rails database tests, node unit/race tests on Linux and Windows targets where available, frontend type/build tests, and broader cached suites.
- [x] Review git diff and status; stage only the exact owned files above.
- [ ] Commit directly to CE main with no feature branch and no push.
- [ ] Report exact checks, commit ID, remaining CNB/platform gaps, and unchanged unrelated work.

### Phase 5A — independent P1 safety-review closure

- [x] P1-1 recovery resolution: add a dedicated permission, step-up authorization, explicit reason, optimistic lock contract, idempotency key, append-only event/audit trail, and Arco Admin action for resolving `recovery_required`. Resolution must be driven by a v2 node reconciliation operation and may reach a non-blocking terminal state only after the node durably proves the live world is the selected tree, the pre-restore tree is restored, or the original absent state is restored; database-only clearing is forbidden and every ambiguous/error state remains fail-closed.
- [x] P1-2 sensitive-action throttling: reuse or extract a CE-owned backend limiter for world-restore authorization failures keyed by user, request IP, and action scope. Password, TOTP, and recovery-code failures share the same non-disclosing counter; escalating/fixed-window lockout is enforced before credential verification, successful verification clears or decays the bucket, and audit plus Simplified Chinese/English errors are provided.
- [x] P1-3 execute/configuration serialization: enforce one stable database lock order for restore plan then server, repeat the complete node/server/backup/stopped/capability/configuration contract inside that transaction, and bind the node operation plus consume authorization while those locks remain held. Server restore-target updates must take the mutually exclusive server lock/optimistic-lock contract so no stale configuration can commit between final validation and enqueue binding; add concurrency-race test source without running it locally.

### Phase 5B — incremental P1 lifecycle and throttling closure

- [x] P1-A atomic sensitive-action reservation: replace split check/failure accounting with one database-row-locked reserve operation that atomically evaluates and occupies both the user and shared-IP buckets before any password, TOTP, or recovery-code verification. A blocked reserve must never invoke credential verification; failure converts the exact reservation into fixed-window failure history, success settles only that exact attempt without clearing another user's shared-IP history, and abandoned reservations cease counting after a bounded TTL. Add source coverage for concurrent attempts against different plans, different users sharing one IP, and successful verification preserving prior IP protection.
- [x] P1-B recovery-resolution lifecycle ownership: give planned/authorized resolutions short server-enforced expiries, explicit audited cancellation, and an audited takeover/replan operation limited to the independent recovery permission plus fresh step-up verification, explicit reason, request idempotency, and exact plan/resolution lock versions. Takeover must preserve the former actor, authorization, events, node proof, and resolution record; create a new actor-bound planned resolution whose token contract cannot reuse the prior authorization. Keep database partial indexes, triggers, Rails state machines, Arco Admin controls, and Simplified Chinese/English source tests synchronized.

### Phase 6 — downstream handoff outside this CE task

- [ ] After the parent confirms the wider development set is ready, merge the exact CE commit into EE and then EE-PVP by ordinary merges only.
- [ ] Run downstream-focused verification after each merge.
- [ ] Do not copy, cherry-pick, squash, rebase, recreate, or push from this scoped CE task.

## Acceptance matrix

- Selection safety: Admin can choose only an available managed backup ID for the same server/node; no request field accepts an archive/destination path.
- Authorization safety: unauthorized, stale, replayed, expired, mismatched-confirmation, configuration-changed, and capability-downgraded requests fail before enqueue.
- Process safety: database and real driver running/unknown states fail; start/restart/config changes remain blocked through active or unresolved recovery.
- Archive safety: every required malicious entry class fails before live mutation and leaves no trusted staging tree.
- Integrity: archive, full manifest, entry set/order, per-file size/digest, and installed tree all agree.
- Atomicity: users never receive a partially extracted live world; each crash point converges to a verified new tree, verified old tree, or explicit recovery_required block.
- Rollback: a durable pre-restore snapshot precedes cutover; automatic rollback is verified and auditable; later operator rollback uses a new authorized plan.
- Idempotency: duplicate HTTP, Sidekiq, node delivery/result/ack, and process restart paths produce one logical backup/plan/operation/outcome.
- Observability: Admin and audit expose IDs, phase, sizes/counts, safe digest suffixes, and stable errors without secrets or filesystem paths.
- Experience: Simplified Chinese/English, keyboard use, mobile layout, warnings, disabled blockers, step-up inputs, typed confirmation, and refresh remain coherent.
- Compatibility: legacy restore execution is retired safely; older nodes and incomplete/new unknown capabilities fail closed; existing archives/history are preserved.
