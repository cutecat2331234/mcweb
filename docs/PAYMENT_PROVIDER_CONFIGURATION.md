# Payment provider configuration operations

This runbook covers the CE Stripe provider configuration page at
`/admin/store/payment-providers` and the reconciliation console at
`/admin/store/payment-reconciliations`. These controls do not change the
existing checkout, refund, or inbound Webhook processing flow.

## Security boundary

- `Payments::ProviderConfig` encrypts the credential JSON with Lockbox in
  `encrypted_credentials`.
- The controller and Inertia props expose only boolean credential-presence
  flags. They never return plaintext credentials, encrypted ciphertext,
  fingerprints, or partial credential suffixes.
- A blank credential input preserves the saved value. Removing a credential
  requires its explicit removal checkbox.
- Request logging filters `secret`, `token`, and key-like parameter names.
- Configuration audit records contain provider, mode, enabled/readiness flags,
  and changed field names only.
- The current Stripe account ID is never stored. A successful connection probe
  derives a domain-separated HMAC-SHA256 fingerprint using the Lockbox key and
  stores only that 64-character digest.

Keep `LOCKBOX_MASTER_KEY` stable and backed up. Losing or changing it without a
planned Lockbox key-rotation procedure makes saved provider credentials
unreadable and invalidates the account fingerprint comparison.

## Account-binding release gate

Migration `20260726125802_bind_stripe_account_identity.rb` invalidates legacy
connection-test successes because those tests did not prove a Stripe account
identity. Before running this migration in any environment, run the mandatory
read-only preflight:

```bash
RAILS_ENV=production bundle exec ruby scripts/check-stripe-account-binding.rb
```

The command prints only booleans and a safe code. Exit status `0` permits the
release. Exit status `1` with
`stripe_account_binding_release_blocked` means Stripe financial history exists
but no verified fingerprint is stored. Stop the release: do not run the
migration, do not edit the database, and do not calculate or paste a
fingerprint manually. This development wave supports automatic first binding
only when there is no Stripe financial history. A historical installation
requires a separately reviewed, audited recovery release before this wave can
be deployed.

Exit status `1` with `stripe_account_binding_disable_required` means the
unbound provider is still enabled. Disable Stripe and drain in-flight checkout
and Webhook delivery before retrying the release preflight. The new release
rejects Stripe Webhooks with retryable HTTP 503 until account identity and the
current credential revision are verified; it never persists those rejected
events.

Stripe financial history includes any local Stripe payment record, financial
Stripe Webhook event, reconciliation observation, or reconciliation
discrepancy. An empty reconciliation run skipped because the provider was not
configured is not financial history.

Once an installation is bound, changing Stripe keys for the same account is
allowed after a successful retest. A different account is rejected with
`account_mismatch`; the stored binding is never overwritten automatically.

## Permissions

Two dedicated permissions are created by migration
`20260726125400_add_payment_provider_configuration_management.rb`:

- `store.payments.configure` — view and update provider mode, credentials, and
  enabled state.
- `store.payments.connection_test` — run a confirmed external connection test.

The migration grants both permissions only to the built-in `owner` and
`super_admin` roles. Connection testing also requires access to the
configuration page, an unexpired version-bound token, and typing `stripe`
exactly in the confirmation dialog.

Migration `20260726125700_create_payment_reconciliations.rb` creates the read
and review permissions:

- `store.payments.reconciliation.read` — view reconciliation runs and
  discrepancies.
- `store.payments.reconciliation.review` — review a discrepancy.

Migration `20260726125901_add_payment_reconciliation_run_permission.rb` adds
`store.payments.reconciliation.run` for the separate high-risk action. A manual
run requires both read and run permissions; review permission alone cannot
queue provider work. The built-in `owner` and `super_admin` roles receive all
three permissions.

## Safe enablement sequence

1. Configure a valid production public URL in `MCWEB_PUBLIC_URL`. Production
   must use HTTPS.
2. Open **Admin → Store → Payment providers**.
3. Select `test` or `live`. The secret key must use the matching `sk_test_`,
   `rk_test_`, `sk_live_`, or `rk_live_` prefix.
4. Save the Stripe secret key and `whsec_` Webhook signing secret while the
   provider is disabled.
5. Resolve every local Webhook configuration check.
6. With the dedicated connection-test permission, confirm and run the
   connection test.
7. Enable Stripe only after the expected environment and account have been
   verified.

Disabling Stripe removes it from checkout without deleting its encrypted
credentials.

## Webhook setup

Register the endpoint shown on the page in the matching Stripe environment. Its
path is:

```text
/app/store/webhooks/stripe
```

Subscribe to the event list displayed on the page. It is generated from the
allowlisted success and failure events in `Payments::StripeProvider`.

The Webhook check is local-only. It verifies the Rails POST route, public URL,
production HTTPS requirement, signing-secret format, and test/live alignment.
It never contacts Stripe and never returns the signing secret.

## Connection test behavior

The connection test performs read-only Stripe Balance and current-account
requests through the official SDK. It:

- has a five-second application timeout;
- is bound to the provider ID, mode, encrypted-credential revision, and
  `updated_at`;
- becomes invalid when the configuration changes or after ten minutes;
- validates the returned `acct_` identifier strictly, derives its HMAC
  fingerprint in memory, and discards the plaintext account ID;
- stores only `success`/`failed`, mode, credential revision, account
  fingerprint, time, actor, and an allowlisted safe error code;
- requires the successful mode and encrypted-credential revision to remain
  current before checkout or reconciliation can run;
- writes an immutable `admin.payment_provider_connection_tested` audit event
  without credentials or provider response data.

Automated tests inject a fake probe and do not access the public network.

## Reconciliation network budget

Reconciliation creates a dedicated `Stripe::StripeClient` and changes only the
request configuration cloned into that client. It never mutates the
process-wide `Stripe.config`, so a reconciliation job cannot change timeout or
retry behavior for concurrent checkout, refund, Webhook, or connection-test
requests.

The installed stripe-ruby version does not expose timeout fields in the public
`StripeClient` constructor. McWeb therefore verifies the current client's
isolated request-configuration contract before applying these values and fails
closed if a future SDK version no longer provides it.

The following environment values are optional:

| Variable | Default | Accepted range |
| --- | ---: | ---: |
| `MCWEB_STRIPE_RECONCILIATION_OPEN_TIMEOUT_SECONDS` | 5 | 1–5 seconds |
| `MCWEB_STRIPE_RECONCILIATION_READ_TIMEOUT_SECONDS` | 15 | 1–19 seconds |
| `MCWEB_STRIPE_RECONCILIATION_WRITE_TIMEOUT_SECONDS` | 5 | 1–5 seconds |
| `MCWEB_STRIPE_RECONCILIATION_MAX_NETWORK_RETRIES` | 1 | 0–1 retry |
| `MCWEB_STRIPE_RECONCILIATION_NETWORK_RETRY_DELAY_SECONDS` | 1 | 0–2 seconds |

An integer outside its accepted range is clamped to the nearest safe boundary.
A blank or non-integer value uses the default. The retry-delay value replaces
both the SDK initial and maximum network retry delay, preventing a larger
global SDK delay from leaking into this client.

The conservative configured envelope is:

```text
(open + read + write) × (retries + 1) + retry_delay × retries
```

The accepted ranges keep that value at or below 60 seconds. This is a
per-Stripe-page request budget, not a hard deadline for a complete daily run.
Net::HTTP timeouts govern individual network phases, and reconciliation may
read multiple payment and refund pages. Operators must therefore expect a
large day to take longer than 60 seconds while every individual provider page
remains bounded.

## Daily and manual reconciliation

The scheduled maintenance job fans out the previous seven completed UTC days
as independent jobs. A retry or permanent failure for one date therefore does
not refresh or block another date. Each run is unique by provider, mode, UTC
window start, and UTC window end.
Stripe pages are read-only; reconciliation can create or resolve discrepancy
records but never changes orders, payments, refunds, balances, or provider
funds.

An operator with reconciliation read and run permissions can request one date from the
reconciliation console. The server enforces all of the following regardless of
browser state:

- the date must use exact `YYYY-MM-DD` form;
- only completed UTC days are eligible, from UTC yesterday back through 365
  days inclusive;
- Stripe must have complete credentials, a current successful connection test,
  and the previously bound account fingerprint;
- checkout does not need to be enabled, so a disabled provider can still be
  reconciled safely;
- fake-only Developer Mode cannot start a Stripe reconciliation;
- the authorization token expires after ten minutes, is bound to the selected
  UTC date, actor, provider configuration record, mode, and configuration
  `updated_at`, and its nonce can be consumed only once;
- any provider configuration change invalidates the token;
- actor, hashed IP, and global request limits are 3, 6, and 20 per 15 minutes;
  at most three other recent pending or actively leased runs may exist;
- the operator must enter `RECONCILE YYYY-MM-DD UTC` exactly. This confirmation
  phrase is intentionally not translated.

The page and date-authorization response use `Cache-Control: no-store`. They
include action material only when the actor has the dedicated run permission
and the current Stripe configuration is reconciliation-ready.

### Locking, duplicate suppression, and audit

The request transaction locks the Stripe configuration and the unique
reconciliation-run row. The existing worker lease remains authoritative:

- an active run lease has a 15-minute heartbeat window and wins over a manual
  request;
- a recently pending run is treated as already queued;
- an immutable recent manual-request audit for the same run suppresses another
  submission for 15 minutes, even if the first run completed quickly;
- browser loading/disabled state blocks accidental double-clicks, while the
  database locks and audit window provide the server-side guarantee;
- duplicate submissions return the existing state and neither queue a second
  job nor append another request audit.

An accepted request writes
`admin.payment_reconciliation_requested` against the reconciliation run. Audit
metadata contains only provider, mode, and date. The audit record also carries
the standard run identity, actor, IP-address, and user-agent fields; it does not
contain credentials, full provider references, cursors, or lease tokens.

The request reserves the run as `pending`, then queues
`Payments::DailyReconciliationJob` with the chosen ISO date, `refresh: false`,
the reserved run ID, and an opaque HMAC binding to the credential revision,
mode, account fingerprint, and run window. Before any Stripe I/O, the worker
revalidates that binding and uses the captured credential snapshot. A changed
configuration fails the original run with `provider_configuration_changed`;
it never switches to a new mode/account or creates a replacement run. The
worker then claims the normal lease. Because the reservation is pending, the
first worker performs a fresh pass; another worker that already completed that
reservation causes the manual job to return without refreshing it a second
time.

If the queue adapter rejects the enqueue, the run becomes `failed` with
`manual_enqueue_failed`. That code bypasses the recent-request cooldown so the
operator can retry immediately; the original audit remains as evidence of the
failed request. Once running, `rate_limited`, `provider_unavailable`,
`provider_error`, and `reconciliation_internal_error` use the maintenance
job's bounded retry policy of five total attempts with polynomial backoff.
Other safe failure codes remain visible on the run for investigation instead
of being retried blindly.

Operational procedure:

1. Confirm the current Stripe mode and connection test on **Admin → Store →
   Payment providers**.
2. Open **Admin → Store → Payment reconciliation**.
3. Review recent runs to avoid requesting a date already being processed.
4. Choose one eligible UTC date and enter the displayed exact confirmation.
5. Submit once and confirm the run appears as pending or running.
6. Inspect the final run counts and discrepancy list. Resolve provider or
   configuration failures before submitting another pass.

## Verification

```bash
PARALLEL_WORKERS=1 bundle exec rails test \
  test/services/payments/provider_configuration_management_test.rb \
  test/services/payments/stripe_account_binding_preflight_test.rb \
  test/services/payments/stripe_reconciliation_client_test.rb \
  test/services/payments/request_manual_reconciliation_test.rb \
  test/jobs/payments/daily_reconciliation_job_contract_test.rb \
  test/integration/admin/payment_providers_admin_test.rb \
  test/integration/admin/payment_reconciliations_admin_contract_test.rb
bundle exec rubocop \
  app/models/payments/provider_config.rb \
  app/controllers/admin/store/payment_providers_controller.rb \
  app/services/payments
npm run typecheck
node scripts/check-frontend-i18n.mjs
ruby scripts/check-rails-i18n.rb
```

Before a production launch, complete a manual Stripe test-mode smoke test in
the intended account and confirm Stripe Dashboard deliveries reach the HTTPS
endpoint. Automated local checks do not prove external DNS, TLS, firewall, or
Stripe Dashboard subscription state.
