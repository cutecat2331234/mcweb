# Minecraft identity lifecycle contract

## Ownership decision

Minecraft account binding is a shared identity capability used by every McWeb
edition, so CE owns the lifecycle adapter. EE and EE-PVP must consume this CE
history through ordinary downstream merges. Product-specific applications,
tickets, queues, Tier rules, and review workflows remain downstream and may
only participate through the existing bounded unlink-restriction extension.

## Task checklist

- [x] Inspect the account-closure and data-export contributor contracts before
      implementation.
- [x] Classify modern identity links, legacy user-owned identities, shared
      player profiles, public identity facts, skin attachments, primary-account
      history, active sessions, and node operations.
- [x] Register one CE Minecraft data-export contributor.
- [x] Register one CE Minecraft account-closure contributor.
- [x] Add focused database coverage for privacy, preflight, execution,
      compensation, idempotency, and shared-profile preservation.
- [x] Pass focused tests, RuboCop, and Zeitwerk validation.
- [ ] Merge the CE history through EE into EE-PVP without recreating it.

## Functional requirements

### Personal data export

1. The Minecraft module exports only bindings whose `user_id` belongs to the
   requesting user.
2. Each modern binding may contain the shared player public ID, current-primary
   flag, link time, unlink time, and the active public Minecraft identity facts:
   platform, external UUID, username, identity type, and identity-valid-from
   time.
3. A user-owned legacy identity not represented by a modern identity link is
   exported with the same bounded public facts and necessary link timestamp.
4. Output order and file paths are deterministic so retries produce a stable
   shape. An empty account list remains a valid completed contribution.
5. The module must not export verification/link codes, digests, encrypted
   values, internal tokens, idempotency keys, raw node/task errors, integration
   payloads, audit internals, staff decisions, staff/user identifiers belonging
   to anyone else, private profile metadata, remote skin URLs, texture hashes,
   or any Active Storage skin/cape binary.
6. Primary-account requests and events are retained as operational history but
   are not part of this public personal export because they can contain staff
   identities, internal reasons, and workflow metadata.

### Account-close preflight

1. Preflight locks no data and mutates nothing.
2. An active Minecraft player session on any currently linked shared profile
   blocks closure with the stable contribution code
   `minecraft_account_close_active_session`.
3. Every current link is checked through
   `Minecraft::IdentityUnlinkRestrictions`. A downstream active workflow,
   pending operation, retention obligation that cannot be preserved safely, or
   unavailable restriction checker blocks closure and exposes its stable code
   in the Minecraft contribution without exposing internal records.
4. Pending primary-account change requests do not block closure because CE can
   cancel them transactionally before the links become inactive.
5. Effective retention holds do not by themselves block closure when link
   history can be retained by soft unlink. The contributor preserves the link,
   timestamps, primary-account history, shared profile, and public identity
   facts. A downstream hold with stricter semantics must deny through the
   restriction extension.
6. Current CE node operations are server-targeted rather than user/link-targeted
   and are neither cancelled nor exported here. Any future operation that owns
   a user binding must add a restriction checker before shipping.

### Transactional closure and recovery

1. Execution locks the user's current links and relevant pending
   primary-account requests in deterministic order inside the surrounding
   account-close transaction.
2. All current links are soft-unlinked at the same closure timestamp and lose
   primary-account status. Historical links and immutable primary-account
   events remain intact.
3. Pending primary-account requests referencing those links are cancelled with
   a stable closure reason. No transient successor is selected while all of a
   closing user's links are being revoked.
4. User-owned legacy `Minecraft::Identity` binding rows are removed only after
   their bounded restoration snapshot is captured. Shared
   `Minecraft::PlayerProfile`, `Minecraft::PlayerIdentity`, permission, session,
   and cached skin/cape records are never deleted by this lifecycle adapter.
5. Execution is idempotent: rerunning after all user bindings are already
   inactive completes without further mutation.
6. Compensation restores exactly the link primary/unlink fields, pending
   request state, and legacy user-owned identity rows captured by that
   execution. It never reconstructs or overwrites shared player facts.
7. A failure in this or any later contributor leaves the account-close
   transaction uncommitted; compensation also satisfies the contributor
   protocol when exercised independently.
8. Binding completion and legacy link-code redemption lock and recheck the user
   before consuming a code, so a concurrent or already completed account close
   cannot create a new active or legacy binding afterward.

## Privacy contract

- The export is an explicit allowlist, not a serialization of model
  attributes or associations.
- Shared Minecraft identity facts may be included only because they are public
  facts attached to the requesting user's own binding; no linked user lookup is
  serialized.
- Skin and cape attachments remain server-side cached shared assets and are
  excluded in both metadata and binary form.
- Account closure changes only ownership/binding state. It does not erase
  shared Minecraft history or evidence needed by retained workflows.
- Public contribution details contain bounded counts and stable reason codes,
  never database IDs, staff names, task payloads, exception messages, or
  verification material.

## Acceptance checklist

- A user with current, historical, primary, and legacy-only accounts receives
  only their own bounded Minecraft records in `minecraft/accounts.json`.
- Another user's link, staff workflow data, secrets, metadata, errors, and skin
  attachments are absent from the generated JSON and ZIP archive.
- No-link export succeeds with an empty deterministic document.
- An online linked player or a registered unlink restriction stops closure
  before any contributor executes and returns a stable Minecraft code.
- Pending primary-account requests are safely cancelled during closure.
- Successful closure leaves no active link or primary account for the user,
  removes legacy user-owned binding rows, and preserves shared profiles,
  identities, attachments, and immutable history.
- Re-execution is a no-op, and injected later failure/explicit compensation
  restores the exact pre-execution binding state.
- A closed account cannot consume a valid link code or recreate either binding
  representation.
- Focused database tests, RuboCop, and Zeitwerk validation pass on the CE
  branch with a clean worktree.
