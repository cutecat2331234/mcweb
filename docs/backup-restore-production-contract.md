# Backup and restore production contract

## Ownership decision

Backup scheduling, retention, object snapshotting, restore verification, and
disaster-recovery evidence are shared host-lifecycle capabilities, so CE owns
them. EE and EE-PVP consume the same contract through ordinary downstream
merges. This work must not introduce enterprise- or PVP-specific data or
workflow concepts.

`DataGovernance::RetentionPolicy` continues to govern application content. It
must not be reused for infrastructure backups: content expiry and recoverable
backup retention have different operators, failure modes, and safety rules.

## Read-only audit baseline

The production scripts already create an atomic PostgreSQL dump, validate its
catalog, checksum local artifacts, and stage local Active Storage files before
publishing a restore. They also isolate configuration secrets from the normal
backup and require an encrypted secret artifact or immutable secret-manager
reference.

Private S3-compatible storage is not currently recoverable from a McWeb
backup. `bin/backup` records an Active Storage object inventory and verifies
that each primary object exists, but it never copies object bytes into a backup
store. `bin/restore` validates that inventory but does not download or restore
objects. The existing MinIO acceptance flow reads the unchanged primary bucket
after restoring the database, so it cannot serve as evidence that an object
snapshot can be recovered. There is also no host schedule, retention policy,
or durable restore-preflight/drill report.

## Task checklist

- [ ] Snapshot every referenced private S3 object into a dedicated backup
      bucket/prefix and verify the uploaded byte count and SHA-256 digest.
- [ ] Record only non-secret immutable object locators and integrity metadata
      in the backup inventory and manifest.
- [ ] Make verify-only restore download every snapshot object and validate its
      digest without changing the database or primary object store.
- [ ] Make apply restore publish verified object bytes to an isolated target
      store before restoring the database, with idempotent retry behavior and
      collision refusal.
- [ ] Persist checksum-covered preflight and apply/drill reports whose failure
      codes are actionable but contain no credentials or secret-bearing URLs.
- [ ] Add a single-instance host maintenance entry point with configurable
      schedule and bounded retention by age and minimum retained generations.
- [ ] Audit completed and failed runs using stable identifiers, stage names,
      counts, and redacted error classes only.
- [ ] Add focused contract and failure-path tests without requiring a real
      external cloud account.
- [ ] Keep a real external-store restore drill, RPO/RTO measurement, bucket
      versioning/immutability review, and operator sign-off as production
      gates rather than claiming them from local tests.
- [ ] Merge the CE history through EE into EE-PVP.

## Functional requirements

### Private object snapshots

1. A private-S3 backup requires an explicitly configured backup bucket and an
   immutable per-backup prefix. Backup credentials may come from the process
   environment or the standard AWS credential chain, but must never be written
   to manifests, reports, command lines, logs, or audit metadata.
2. Each Active Storage object is streamed to a restricted temporary file while
   calculating SHA-256 and byte count, then uploaded under the immutable backup
   prefix. The uploaded copy is downloaded and hashed again before the backup
   can be published.
3. A retry may reuse an existing snapshot object only when its byte count and
   SHA-256 match. A mismatched object at the same key is an immutable collision
   and fails closed.
4. The inventory records the original object key, backup key, non-secret bucket
   name, byte count, SHA-256, Active Storage checksum, and verification state.
   It must not include access keys, session tokens, signed URLs, endpoint query
   strings, or raw exception messages.
5. A backup remains unpublished until the database dump, configuration
   contract, object inventory, and every remote snapshot have passed integrity
   checks.

### Verify and restore

1. Verify-only mode is non-mutating. It validates manifest/checksum coverage,
   the PostgreSQL archive, and every remote snapshot's byte count and SHA-256.
2. Apply mode requires the existing new/empty database and isolated-target
   guards. It stages and verifies snapshot bytes before writing them to the
   target object store.
3. A target object that already matches may be reused on retry. A target object
   with different bytes must never be overwritten implicitly.
4. Remote objects are completed before the single-transaction database
   restore. Therefore an object failure leaves the database empty and
   retryable; a database failure may leave verified target objects that a retry
   can safely reuse.
5. Applying a legacy inventory-only private-S3 backup is rejected with an
   executable explanation. It must never be presented as a complete restore.

### Reports and audit

1. Every verify or apply attempt writes an atomic JSON report to an explicitly
   configured evidence directory. The report identifies the backup, mode,
   stage, outcome, object counts, manifest digest, and UTC timestamps.
2. Reports use stable bounded error codes and error classes. Raw exception
   messages, environment values, connection strings, endpoints, bucket URLs,
   database DSNs, filenames supplied by users, and credentials are excluded.
3. A report is checksum-covered or chained to the verified manifest so an
   operator can determine exactly which backup was inspected.
4. A local MinIO exercise may prove the software path and failure handling, but
   its report must identify the environment as local acceptance evidence. Only
   an operator-run external-store exercise may be labelled a production drill.

### Scheduling and retention

1. The host maintenance entry point holds an exclusive lock, invokes the same
   production backup and verify paths, and exits non-zero on either failure.
2. Schedule, backup root, retention age, and minimum generation count are
   explicit environment/configuration values with bounded validation.
3. Retention considers only complete backup directories containing a valid
   manifest. It keeps at least the configured minimum and never follows
   symlinks or deletes outside the resolved backup root.
4. A failed or incomplete generation is retained for diagnosis and is not
   mistaken for the latest verified recovery point.
5. Remote snapshot deletion is restricted to keys named by a verified
   inventory beneath the configured backup prefix. Broad bucket deletion is
   forbidden.

## Acceptance checklist

- A private-S3 backup fails before publication when its backup bucket/prefix is
  absent, an object cannot be read, an uploaded copy cannot be re-downloaded,
  or either digest differs.
- Removing or corrupting the primary object after backup does not prevent
  verify-only mode from validating the independent snapshot.
- Applying into an empty database and empty target bucket restores the object
  bytes and database references; downloading through Active Storage returns
  the original bytes.
- Repeating apply after an interrupted run reuses matching target objects and
  still refuses mismatched collisions.
- A legacy manifest-only private-S3 backup remains verifiable only as legacy
  metadata and cannot be applied as a full disaster recovery.
- Reports exist for success and failure and contain no credentials, signed
  URLs, DSNs, endpoints, or raw exception messages.
- Retention preserves the configured minimum verified generations, refuses an
  unsafe root, and cannot delete an unrelated directory or object key.
- Focused tests, shell syntax checks, RuboCop, Zeitwerk, and database-backed
  tests pass on the CE branch.

## Production gates and non-goals

- Repository tests and local MinIO acceptance do not prove cloud-provider
  IAM, networking, lifecycle, versioning, object-lock, encryption-key recovery,
  capacity, throughput, or regional-failure behavior.
- Before production enablement, an operator must restore a fresh backup into an
  isolated external database and object store, verify representative downloads,
  measure RPO/RTO, record evidence, and obtain sign-off.
- This contract does not turn Rails content-retention policies into backup
  retention, run root-level host jobs in Sidekiq, copy EE/PVP data semantics
  into CE, or log secret configuration for diagnostic convenience.
