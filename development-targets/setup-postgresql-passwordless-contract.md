# PostgreSQL passwordless setup contract

## Ownership and boundaries

- Owner: CE.
- Reason: database connection configuration, installation safety, and secret handling are shared platform contracts used by every McWeb edition.
- Inheritance: EE and EE-PVP consume this work only through ordinary `CE -> EE -> EE-PVP` merges after CE verification and commit by the parent workflow.
- Scope: the Rails setup wizard, CE database connection services, local configuration, focused source contracts, and setup copy.
- Exclusions: no shared route changes, no global Vue locale changes, no EE/PVP concepts, and no custom component or stylesheet work.

## Product problem

The backend can legitimately connect to PostgreSQL without a stored password, while the setup flow historically treated a blank password as incomplete. The first fix made the password input optional, but the complete installation contract must also cover local socket/peer and trusted or externally authenticated connections, keep an explicit blank distinct from an omitted field, avoid reflecting connection secrets or infrastructure details, and preserve ordinary password deployments.

## Functional task list

- [x] Accept an explicitly submitted empty database password and preserve it as an intentional passwordless configuration.
- [x] Reject a missing database password field as an invalid or stale submission before any connection attempt or configuration write.
- [x] Allow an empty host and port to select libpq defaults, including the platform's default local PostgreSQL socket; continue validating every explicitly supplied network host and port.
- [x] Allow an empty username to select libpq's operating-system/default user for local peer authentication; preserve explicitly supplied usernames.
- [x] Build PG and Active Record connection options by omitting defaulted host, port, and username keys while retaining an explicitly empty password value; never convert a missing password field into an empty credential.
- [x] Keep password-based TCP deployments behavior-compatible: supplied host, port, username, and non-empty password reach both the connection probe and saved runtime configuration unchanged.
- [x] Return stable localized setup errors for invalid input, connection failure, and database preparation failure without echoing exception messages, credentials, connection URLs, hostnames, usernames, database names, or filesystem paths.
- [x] Use the existing setup form controls and `mc-*` UI classes; add only concise help text and no new styles or component system.
- [x] Add focused source coverage for explicit blank versus missing password, local socket defaults, network password compatibility, safe option construction, and non-reflective failures.

## Contract details

- `password: ""` means the operator intentionally selected a connection that does not store a password. The value remains explicit in `config/local.yml` so setup completeness can distinguish it from an incomplete record.
- No `password` key, or a `null`/non-string password value, means the request contract is malformed. Only the explicit string `""` selects passwordless behavior. The wizard and direct finalization service reject malformed input without probing PostgreSQL.
- Blank host, port, or username means “let libpq use its platform default.” These defaulted keys are omitted from PG and Active Record connection hashes rather than serialized as empty strings or zero. An explicitly blank password remains present as `""` so ambient password configuration cannot silently replace the operator's choice.
- A non-blank password is passed and saved byte-for-byte. Whitespace is not stripped from secrets.
- Connection and preparation failures expose only a stable user-facing category. Detailed exceptions remain server-side concerns and must not be interpolated into setup responses.

## Acceptance checklist

- [ ] Passwordless TCP/trust: a form payload with host, port, username, and `password: ""` reaches the probe, persists the explicit blank, prepares the database, and advances to the site step.
- [ ] Local socket/peer: a form payload with blank host, port, username, and password uses libpq defaults and advances when the connection succeeds.
- [ ] External authentication: an IAM/local authentication proxy or externally authenticated PostgreSQL endpoint can submit an explicit blank password without client-side or server-side presence rejection.
- [ ] Missing-field safety: omitting the password key never triggers a connection attempt, config write, or database preparation.
- [ ] Compatibility: an existing host/port/username/password submission produces the same explicit connection options and saved values as before.
- [ ] Secret safety: a raised error containing a password, URL, token, host, user, database, or socket path is not reflected in the flash or service result returned to the user.
- [ ] UI consistency: the setup page uses only existing form classes and clearly explains optional/defaulted connection fields without custom styling.

The acceptance items remain unchecked because this scoped task explicitly forbids tests, builds, static tooling, browser acceptance, and CNB. Source inspection and the authored coverage are complete; execution evidence is deferred.
