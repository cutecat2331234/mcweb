# Identity two-factor enrollment hardening

## Ownership and current snapshot

- Owner: CE.
- Reason: sign-in assurance, account credentials, session invalidation, audit records, and security notices are shared identity-platform responsibilities. EE and EE-PVP must inherit this work through ordinary `CE -> EE -> EE-PVP` merges.
- Re-audited from CE `main` at `582bb32822b90b4bfceb8468e6e673766404a99a` on 2026-08-24. Historical audit conclusions were not used as current-state evidence.

## Account/Identity journey matrix

Legend: **Closed** means the journey has a reachable UI and a server-side completion/recovery path; **Partial** means it is reachable but leaves a security or lifecycle gap; **Missing / unreachable** means the user has no usable entry or completion path.

| User journey | Closed | Partial | Missing / unreachable | Current-source evidence |
| --- | :---: | :---: | :---: | --- |
| Sign in, including the second-factor challenge | Yes |  |  | `Identity::SessionsController` verifies credentials before creating a bounded second-factor challenge; `Identity/Sessions/TwoFactor.vue` accepts TOTP or a one-time recovery code and links to email recovery. |
| Enable two-factor authentication |  | Yes |  | The security page reaches setup and confirmation, and the controller rejects stale setup secrets. Confirmation currently accepts only the new TOTP code: it does not re-verify the account password, revoke sessions authenticated before enrollment, or rotate the current session token. |
| Recovery codes and locked-out recovery | Yes |  |  | Codes are shown once after enrollment, can be regenerated only with password plus current second factor, are consumed atomically at sign-in, and verified-email recovery disables TOTP while revoking every session. |
| Change sign-in email | Yes |  |  | Password/current-factor reauthentication creates a pending request; the replacement address confirms it, the old address can cancel or reverse it, and confirmation/reversal revoke affected sessions with audit records. |
| Change password | Yes |  |  | The current password and current factor are required; other sessions are revoked, the current token is rotated, reset state is cleared, an audit record is written, and a security email is queued. |
| Review and revoke sign-in sessions | Yes |  |  | The account center and security page link to the active-session list; a user can revoke each other session, while the ordinary sign-out path revokes the current session. The controller also fails ownership lookup closed. |
| Close account | Yes |  |  | The security page exposes the destructive flow; password/current-factor confirmation, owner safety, contributor preflight, profile anonymization/content policy, credential clearing, session/API-key revocation, persisted outcomes, and audit are handled transactionally. |
| Request and retrieve an account data export | Yes |  |  | The account center and security page link to export history; requests have an idempotency key and daily limit, then expose queued/running/completed/failed/expired state, retry, revocation, expiring download, manifest, and audit behavior. |

No Account/Identity journey in the requested scope is wholly missing or unreachable in the current tree. Two-factor enrollment is the only high-confidence incomplete security closure found in this pass.

## Selected development target

Close two-factor enrollment as one atomic, reauthenticated session transition:

- Require the current account password and the newly enrolled authenticator code before enabling TOTP.
- Require a still-active, user-owned current session and fail closed if it disappeared or belongs to another user.
- Lock the user and current session, reject stale setup secrets, and enable only the secret shown in the requesting browser.
- Revoke every other active sign-in session created before enrollment and rotate the preserved current session token.
- Keep duplicate confirmation safe: a replay for the same enabled secret must not rotate twice, write a second audit record, or send a second notice.
- Continue showing the generated recovery codes once, without placing the TOTP secret, password, session token, or recovery codes in audit metadata.
- Record the verification method and revoked-session count through the existing audit logger.
- Send a localized security email through the existing identity mailer and queued mail-delivery primitive, including recovery guidance when the enrollment was not initiated by the recipient.
- Reuse the current security page components and bilingual i18n sources; add no route, entrypoint, layout, navigation, or frontend-boundary primitive.

## Scoped implementation files

- `app/services/identity/enable_totp.rb`
- `app/controllers/identity/security_controller.rb`
- `app/javascript/pages/Identity/Security/Show.vue`
- `app/javascript/locales/en.ts`
- `app/javascript/locales/zh-CN.ts`
- `app/mailers/identity/mailer.rb`
- `app/views/identity/mailer/totp_enabled_email.html.erb`
- `app/views/identity/mailer/totp_enabled_email.text.erb`
- `config/locales/mcweb.en.yml`
- `config/locales/mcweb.zh-CN.yml`
- `test/services/identity/enable_totp_test.rb`
- `test/integration/identity_security_lifecycle_test.rb`
- `test/javascript/identity_two_factor_enrollment_test.ts`
- `test/mailers/user_facing_mailer_i18n_test.rb`

## Explicit exclusions

- Do not edit application-boundary files, routes, frontend registries, entrypoints, layouts, global navigation, Forum, Commerce, Minecraft, PVP, or EE code.
- Do not stage, commit, merge, or push.
- Do not run tests, builds, type checks, lint, syntax checks, browsers, services, or CNB in this task.

## Delivery checklist

- [x] Move TOTP confirmation into a reauthenticated, locked, replay-safe service.
- [x] Revoke other active sessions and rotate the preserved current session token.
- [x] Preserve one-time recovery-code presentation without logging secrets.
- [x] Add the localized security email and recovery guidance.
- [x] Add focused service, integration, UI-source, and mailer test coverage.
- [x] Review only the scoped diff and report all modified paths without executing verification commands.

## Deferred verification

- Per task boundary, no tests, builds, type checks, lint, syntax checks, browser checks, services, or CNB were run.
- The new test sources are intentionally left for the parent delivery flow to execute when that boundary is lifted.
