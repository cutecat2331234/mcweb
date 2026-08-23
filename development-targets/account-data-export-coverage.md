# Account data export coverage

## Ownership and scope

- Owner: CE.
- Reason: account data rights and the contributor registry are shared identity-platform contracts inherited by every edition.
- Downstream editions add their own contributors through the existing registrar; they must not copy CE contributors.
- This change extends the existing durable export archive. It does not create a second export path or expose staff-only operational records.

## Product requirement

The account export must contain the personal data a member can create or configure across the CE forum and store, not only their profile, authored topics/posts/messages, orders, memberships, and entitlements. The archive must remain useful without exposing another member's private choices, provider payloads, security tokens, staff-only notes, fraud signals, webhook bodies, or internal retry diagnostics.

## Functional checklist

- [x] Export member-created forum bookmarks, reactions, saved searches, profile posts, and profile-post comments.
- [x] Export relationships initiated by the member: followed, blocked, and ignored accounts. Do not reveal who blocked or ignored the member.
- [x] Export the member's points balances and ledger entries without internal deduplication tokens.
- [x] Export store wishlist items and presets, product availability alerts, reviews, helpful votes, and product questions.
- [x] Export the member's payment, refund, and customer-visible dispute lifecycle for their own orders.
- [x] Exclude raw payment request/response metadata, webhook payloads, provider error bodies, staff notes, risk classifications, internal idempotency keys, and security credentials.
- [x] Keep deterministic ordering and stable JSON paths so repeated exports of unchanged data are comparable.
- [x] Register the new CE contributors in the existing frozen catalog.
- [x] Add focused source coverage for catalog registration, empty-account determinism, relationship privacy, and sensitive-field allowlists.
- [ ] Run the focused and full data-export suites in the centralized CNB pipeline.
- [ ] Inspect a generated archive from a representative account before production release.

## Data ownership rules

- A relationship is exported only when the requesting member initiated it. Incoming block/ignore relationships are intentionally excluded because revealing them would disclose another person's private safety choice.
- Commerce records are selected through orders owned by the requesting member, not through mutable request parameters.
- Dispute events expose only lifecycle facts that can be shown to the customer. Internal notes, metadata, staff identities, request IDs, payload digests, and provider event identifiers stay outside the archive.
- Payment attempts expose status and timestamps only. Raw request and response documents can contain tokens or provider implementation details and are never exported.
- Existing Secure Evidence and upload contributors continue to own binary attachment metadata and authorized files; these contributors do not duplicate attachment storage.

## Deferred validation

No test, build, typecheck, lint, syntax check, browser flow, or CNB job is run while this code is authored. Runtime acceptance remains centralized in CNB, followed by a local Edge inspection of the account export journey.
