# McWeb Plugin SDK v1

McWeb deployment plugins are fully trusted Ruby code. A plugin runs inside the
Rails process with the same privileges as the application: it can call Rails
models, access configured services, read environment variables, and execute
arbitrary Ruby. Capabilities are declarations for compatibility and audit; they
are not permissions and do not form a sandbox.

Only install reviewed plugin source through the deployment process or the
permission-gated Marketplace upload. The backend does not fetch remote packages.

## Plugin layout

The loader recursively finds `mcweb_plugin.yml` below `plugins/`:

```text
plugins/
└── acme-demo/
    ├── mcweb_plugin.yml
    └── plugin.rb
```

The root can be changed with `MCWEB_PLUGIN_DIR`. The manifest entrypoint must be
a relative `.rb` file whose resolved path remains inside that plugin directory.
YAML is parsed with `YAML.safe_load`, without aliases or object deserialization.
Manifests must be valid UTF-8, are read through a 1 MiB bound, and duplicate
mapping keys are rejected instead of silently taking the last value.
These checks improve deployment reliability; they do not make the Ruby code
untrusted-code-safe.

## Manifest

```yaml
id: acme/demo
name: Acme Demo
version: 1.2.0
api_version: "1"
description: Records newly created forum posts
author: Acme
homepage: https://example.com/mcweb/acme-demo
entrypoint: plugin.rb
setup: db/setup.rb
requires:
  acme/base: ">= 1.0.0, < 2.0.0"
capabilities:
  - forum.events.read
  - forum.read
  - forum.write
  - forum.moderate
  - forum.events.publish
  - identity.permissions.read
  - site.features.read
  - site.settings.read
  - plugin.settings.read
  - plugin.settings.write
  - plugin.jobs.read
  - plugin.jobs.enqueue
contributions:
  permissions: config/permissions.yml
  settings: config/settings.yml
  jobs: config/jobs.yml
```

Required fields are `id`, `name`, `version`, and `api_version`.
Required and optional text fields must be strings; for example,
`api_version: 1` is rejected and must be written as `api_version: "1"`.

- `id` uses the strict lowercase `vendor/name` form.
- `version` is SemVer, including optional prerelease and build metadata.
- `api_version` must be `"1"`.
- `requires` maps plugin IDs to RubyGems version requirements.
- `capabilities` contains unique namespaced declarations such as
  `forum.events.read`.
- `contributions.permissions` optionally names a package-local YAML file that
  declares the plugin's global permission descriptors.
- `contributions.settings` optionally names a package-local YAML file that
  declares the plugin's strict settings schema and forward migrations.
- `contributions.jobs` optionally names a package-local YAML file that declares
  the plugin's owned background-job keys and closed argument schemas.
- `entrypoint` defaults to `plugin.rb`.
- `setup` is optional and names a package-local Ruby setup plan.

Unknown fields, duplicate IDs, malformed requirements, missing dependencies,
version mismatches, and dependency cycles are rejected or reported through
diagnostics. Discovered dependency entrypoints load before their dependants,
and dependencies activate before dependants. Duplicate discovered IDs,
dependency cycles, and dependency version mismatches known from the discovered
manifest set are rejected before the affected entrypoints execute, preventing
top-level side effects from an extension that cannot activate.

### Permission contributions and global identity groups

A permission contribution file has one strict root key:

```yaml
permissions:
  - id: acme.demo.orders.view
    group: acme.demo.orders
    title_phrase: permission.order_view.title
    description_phrase: permission.order_view.description
    scope: global
    default: none
```

The permission namespace is the manifest ID with `/` replaced by `.` and `-`
replaced by `_`; `acme/demo-tools` therefore owns `acme.demo_tools.*`. This
keeps contributed keys compatible with the host permission-key contract. Each
ID must include a resource and action, each group must remain in that namespace,
and `mcweb.*` is reserved for the host. The supported v1 scope is `global`;
default recommendations are `none`, `member`, `staff`, or `admin`.

The file is safe-YAML parsed, UTF-8, bounded to 1 MiB and 256 descriptors, and
must remain inside the plugin directory. Unknown or duplicate fields fail
loading before the entrypoint runs. A namespace collision disables the
deterministic losing plugin instead of replacing the existing owner.

`default` is installation guidance only. Activation never creates permissions,
roles, role assignments, or group memberships. Administrators grant contributed
keys through the host's existing roles and global identity groups. Plugins have
only read-only access to their active descriptors and the host-computed result:

```ruby
plugin.api.identity.permission_contributions
plugin.api.identity.permission_contribution(
  key: "acme.demo.orders.view"
)
plugin.api.identity.plugin_permission(
  public_id: user_public_id,
  key: "acme.demo.orders.view"
)
```

`plugin_permission` accepts only an active permission contributed by the calling
plugin. Its immutable result includes allow/deny, account eligibility, grant
reason, role or global-group sources, scope, and the contribution descriptor.
The host remains authoritative: banned or deleted accounts are denied, current
group changes are observed on the next check, and disabling, unregistering, or
resetting a plugin immediately removes its active descriptors.

### Settings schema and versioned storage

`contributions.settings` points to safe YAML that contains a strict JSON Schema
Draft 2020-12 subset. The file is UTF-8, bounded to 1 MiB, duplicate-key
checked, and resolved inside the plugin package. Unknown root, schema, group,
property, or migration fields reject plugin registration before its definition
is activated.

```yaml
schema_version: "2"
groups:
  general:
    title_phrase: acme.demo.settings.groups.general.title
    description_phrase: acme.demo.settings.groups.general.description
    position: 10
  credentials:
    title_phrase: acme.demo.settings.groups.credentials.title
    position: 20

schema:
  $schema: https://json-schema.org/draft/2020-12/schema
  type: object
  additionalProperties: false
  required:
    - endpoint
    - api_token
  properties:
    endpoint:
      type: string
      format: url
      maxLength: 2048
      x-mcweb-title-phrase: acme.demo.settings.endpoint.title
      x-mcweb-description-phrase: acme.demo.settings.endpoint.description
      x-mcweb-group: general
      x-mcweb-input: url
    timeout_seconds:
      type: integer
      default: 10
      minimum: 1
      maximum: 120
      x-mcweb-title-phrase: acme.demo.settings.timeout.title
      x-mcweb-group: general
    api_token:
      type: string
      minLength: 1
      maxLength: 4096
      x-mcweb-title-phrase: acme.demo.settings.api_token.title
      x-mcweb-group: credentials
      x-mcweb-sensitive: true
      x-mcweb-input: password

migrations:
  - from: "1"
    to: "2"
    rename:
      api_url: endpoint
    remove:
      - legacy_debug
    defaults:
      timeout_seconds: 10
```

`schema_version` is a positive integer string and evolves independently of the
plugin SemVer. The object root must explicitly set
`additionalProperties: false`. Supported scalar types are `string`, `integer`,
`number`, and `boolean`; supported validation includes `enum`, string length,
numeric bounds, regular expressions, and `uri`, `url`, `email`, or `hostname`
formats. Arco inputs are selected from `text`, `password`, `textarea`, `url`,
`email`, `select`, `number`, and `switch`.

Every group and field uses a phrase in the plugin namespace (`acme/demo`
becomes `acme.demo.*`). Enum display phrases use
`x-mcweb-enum-phrases`. Default-language phrase loading and coverage belong to
the I18N contribution contract; until that contract is installed, an unresolved
phrase key remains visible as a diagnostic instead of accepting package-provided
hard-coded UI text.

Sensitive properties must be password strings and cannot declare a default or
enum. McWeb encrypts the complete settings payload with Lockbox. The admin page
returns only whether a sensitive field is configured; its plaintext never
appears in page props, version history, audit metadata, or change events. The
trusted plugin runtime can read its own decrypted value because plugin code
already has the full privileges of the Rails process.

Settings are isolated by plugin ID and schema version. Each update appends an
immutable revision instead of replacing history. An upgrade explicitly migrates
the newest compatible older namespace through every declared `from`/`to` step;
the source namespace remains untouched. Rolling the plugin package back therefore
selects its prior schema namespace. If settings are changed while code is rolled
back, the newer schema requires another explicit migration after re-upgrade.
Changing constraints without increasing `schema_version` produces a schema
digest mismatch and blocks reads/writes instead of interpreting old ciphertext
under a different contract.

```ruby
plugin.api.settings.descriptor
plugin.api.settings.values
plugin.api.settings.get("api_token")

plugin.api.settings.update(
  values: {
    endpoint: "https://api.example.test",
    api_token: ENV.fetch("ACME_API_TOKEN")
  },
  expected_revision: 0
)

plugin.api.settings.migrate(expected_revision: 0)
plugin.api.settings.rollback(revision: 1, expected_revision: 3)
```

Declare `plugin.settings.read` and `plugin.settings.write` for compatibility
and capability audit. The facade is constructed with the calling manifest, so
it cannot address another plugin namespace or host `SiteSetting` keys. Results
are immutable v1 `Result` snapshots. Schema, revision, and migration conflicts
have stable error codes; submitted values are never included in errors. Every
write must pass the `expected_revision` from the latest `values` snapshot
(`0` for the first persisted revision). Omitting it returns `invalid_argument`
instead of allowing last-write-wins behavior.

Administrators require the separate `system.plugins.settings.manage`
permission to use **System → Plugin settings**
(`/admin/system/plugin-settings`). Admin mutations require an expected revision.
Rollback appends a validated current-schema revision; it never rewrites an old
row. Every committed mutation creates an immutable `AuditLog` and the
after-commit `plugin.settings.changed` event. Both contain identifiers, schema
digest, revision, change kind, and changed key names only—never old or new
values.

### Owned background jobs

`contributions.jobs` points to a package-local, safe-YAML declaration. The file
is UTF-8, limited to 1 MiB, duplicate-key checked, and resolved by real path
inside the plugin package. Unknown fields and path escapes reject activation.
Jobs are addressed only by a key owned by the declaring plugin; a declaration
cannot name an Active Job or arbitrary Ruby class.

```yaml
schema_version: "1"
jobs:
  deliver:
    max_attempts: 3
    retry_wait_seconds: 60
    lease_seconds: 900
    arguments:
      $schema: https://json-schema.org/draft/2020-12/schema
      type: object
      additionalProperties: false
      required:
        - recipient_id
        - message
      properties:
        recipient_id:
          type: string
          format: uuid
        message:
          type: string
          maxLength: 1024
```

The argument schema is a closed Draft 2020-12 object. It supports flat
`string`, `integer`, `number`, and `boolean` properties, plus enum, string
length, numeric bounds, and supported string formats. A plugin must register
exactly one handler for every declared key before activation:

```ruby
Mcweb::Plugins.register do |plugin|
  plugin.job("deliver") do |arguments, context|
    DeliveryClient.deliver_once(
      operation_id: context.run_public_id,
      recipient_id: arguments.fetch("recipient_id"),
      message: arguments.fetch("message")
    )
  end
end
```

The handler receives revalidated, deeply frozen arguments and a frozen
`JobContext`. The context contains `run_public_id`, owner and job keys, current
attempt, maximum attempts, and the current attempt schedule. Registering an
undeclared key, omitting a declared handler, or reaching across another
plugin's namespace fails registration or the API call.

Declare `plugin.jobs.read` and `plugin.jobs.enqueue` for compatibility audit.
The calling manifest permanently binds the facade to its own namespace:

```ruby
run = plugin.api.jobs.enqueue(
  job_key: "deliver",
  arguments: {
    recipient_id: user.public_id,
    message: "Welcome"
  },
  idempotency_key: "welcome:#{user.public_id}",
  wait_seconds: 0
)

plugin.api.jobs.find(public_id: run.value.fetch("public_id"))
plugin.api.jobs.list(status: "retrying", limit: 25)
plugin.api.jobs.cancel(public_id: run.value.fetch("public_id"))
plugin.api.jobs.resume(public_id: run.value.fetch("public_id"))
```

An idempotency key is required and is unique within the owner plugin and job
key. Repeating the same key and payload returns the original run with
`idempotent: true`; changing the payload or delay returns
`idempotency_conflict`. This guarantees one persisted run, not exactly-once
external effects.

The idempotency key is plaintext operational metadata even though it is omitted
from DTOs, queue payloads, and logs. Use an opaque business operation ID; never
put a password, token, message body, or other secret in the key. Sensitive
values belong only in the encrypted `arguments` object.

Delivery is **at least once**. A worker claims a finite lease and retries
handler failures up to `max_attempts`. If a process dies after an external
effect but before recording success, or a handler runs longer than
`lease_seconds`, another worker can execute the same run concurrently. Set the
lease above the handler's worst-case time, apply timeouts to external calls,
and use `context.run_public_id` as the downstream idempotency key. Cancellation
is supported only before a handler is running and cannot interrupt Ruby code
already executing.

The host persists owner ID, plugin and contribution versions, declaration
digest, status, attempts, lease, and timestamps. It never persists a handler
class name. Arguments are encrypted with Lockbox; Active Job receives only the
opaque run public ID. Arguments and the enqueue idempotency key are omitted
from result DTOs, queue payloads, diagnostics, and error logs. The internal
payload comparison uses a domain-separated HMAC derived from the Lockbox key,
so low-entropy values are not exposed through an ordinary SHA digest.

Keep `LOCKBOX_MASTER_KEY` stable and backed up. A planned key rotation must be
able to decrypt every existing job payload with the old key, re-encrypt it,
and recompute the payload HMAC before the old key is retired. Changing or
losing the key without that migration makes queued payloads unreadable and
breaks idempotency comparison.

When a plugin is disabled, uninstalled, missing, or has a different version or
job declaration, delivery pauses without consuming a handler attempt. A
recoverable uninstall retains the owned run records. Re-enable the exact
compatible version and call `resume`; after an incompatible upgrade, cancel
the old run and enqueue a new run under the new declaration. Do not silently
reinterpret an old payload or delete the ownership records.

## Entrypoint and events

A discovered entrypoint registers exactly its own manifest:

```ruby
# plugins/acme-demo/plugin.rb
Mcweb::Plugins.register do |plugin|
  plugin.on("forum.post.created", priority: 100) do |event|
    Rails.logger.info(
      plugin: "acme/demo",
      event_id: event.event_id,
      post: event.data["post"]
    )
  end
end
```

For code-managed registration, the same DSL accepts manifest attributes:

```ruby
Mcweb::Plugins.register(
  id: "acme/demo",
  name: "Acme Demo",
  version: "1.2.0",
  api_version: "1",
  capabilities: ["forum.events.read"]
) do |plugin|
  plugin.on("forum.post.created", priority: 100) { |event| handle(event) }
end
```

Listeners run synchronously. Smaller priority values run first; ties are ordered
by plugin ID and then declaration order. A plugin listener exception does not
stop later listeners. The failing plugin becomes `degraded`, its failure count
and last error are updated, and a `listener_error` diagnostic is recorded.
Event names are limited to 191 characters. Registration, activation, reset and
reload transitions are serialized; listener failure counters and status
snapshots remain consistent when events arrive concurrently.
Queue slow or retryable work in an application job instead of blocking event
publication.

Each callback receives a frozen `Mcweb::PluginApi::V1::Event`:

```ruby
{
  name: "forum.post.created",
  event_id: "a UUID",
  schema_version: "1",
  occurred_at: "2026-07-24T12:34:56.123456Z",
  data: {
    "post" => {
      "type" => "Community::Post",
      "id" => 42,
      "public_id" => "..."
    }
  }
}
```

`event_id`, `schema_version`, `occurred_at`, and all `data` values are immutable.
Active Record objects are replaced with read-only identity snapshots containing
only `type`, `id`, and `public_id` when available. A callback never receives the
model instance through this event DTO, so attributes such as email, tokens, and
password digests are not serialized. Other unsupported objects become a
type-only snapshot. Collection normalization is bounded to 64 levels; a deeper
branch becomes an immutable `{ "type" => "maximum_depth" }` marker rather than
risking a stack overflow.

### Stable commerce events

Core commerce events are registered with
`ActiveRecord.after_all_transactions_commit` and published through
`Mcweb::Events.defer_until_success`. A listener therefore never observes a
rolled-back payment, refund, inventory movement, or fulfillment transition.
Idempotent service replays do not publish a second event. Handlers should still
use the resource key below when enqueueing an external side effect, because a
job or an external provider can use at-least-once delivery.

| Event | Emitted for | Stable idempotency key |
| --- | --- | --- |
| `commerce.order.paid` | accepted order payment has completed the core paid transition | `order.public_id` |
| `commerce.payment.confirmed` | a pending/processing payment becomes `succeeded` for a payable order | `payment.id` |
| `commerce.payment.failed` | a payment enters the terminal `failed` state; retryable provider notices that leave it pending do not emit | `payment.id` |
| `commerce.payment.refunded` | each completed full or partial refund against a payment | `refund.id` |
| `commerce.refund.requested` | a customer refund request is created | `refund.id` |
| `commerce.refund.processed` | provider confirmation and all local restoration work commit | `refund.id` |
| `commerce.refund.rejected` | a pending refund request becomes rejected | `refund.id` |
| `commerce.inventory.reserved` | an order item creates a stock reservation | `movement.public_id` |
| `commerce.inventory.released` | an active reservation is released or expires; inspect `movement.type` | `movement.public_id` |
| `commerce.inventory.confirmed` | a reservation converts from reserved to sold | `movement.public_id` |
| `commerce.inventory.adjusted` | a signed manual inventory adjustment commits | `movement.public_id` |
| `commerce.fulfillment.dispatched` | a new dispatch attempt enters processing | `fulfillment.delivery_id` + `attempt.number` |
| `commerce.fulfillment.retryable_failed` | an attempt fails and has a scheduled retry | `fulfillment.delivery_id` + `attempt.number` |
| `commerce.fulfillment.failed` | an attempt reaches a terminal/non-retryable failure | `fulfillment.delivery_id` + `attempt.number` |
| `commerce.fulfillment.completed` | a fulfillment first becomes fulfilled | `fulfillment.delivery_id` |
| `commerce.fulfillment.cancelled` | a signed manual cancellation commits | `fulfillment.delivery_id` |

Every payload is an explicit v1 allow-list:

- `order`: `public_id`, `status`, `total_cents`, `currency`;
- `payment`: `id`, `status`, `amount_cents`, `currency`;
- `refund`: `id`, `status`, `amount_cents`, `currency`;
- `inventory`: target/product/variant identifiers plus available, reserved, and
  sold quantities;
- `movement`: `public_id`, type, quantity, and the three quantity deltas;
- `fulfillment`: `id`, stable `delivery_id`, order-item ID, status, attempt
  counts, retry state, and lifecycle timestamps;
- `attempt`: number, trigger, and status; `result` is limited to
  `success/status/error_code/simulated/external_reference`.

Customer identity, username, email, shipping/billing address, free-form reasons,
provider payment/refund references, provider secrets, provider metadata, raw
webhook bodies, and raw connector responses are never included. Use
`commerce.order.paid`—not `commerce.payment.confirmed`—as the normal fulfillment
trigger, because confirmed late/orphan payments intentionally do not make an
order fulfillable.

### Plugin fulfillment providers

A trusted CE plugin can register a synchronous fulfillment adapter without
patching the Minecraft connector:

```ruby
Mcweb::Plugins.register do |plugin|
  plugin.fulfillment_provider("direct") do |request|
    {
      status: "succeeded",
      external_reference: "acme:#{request.fetch("delivery_id")}"
    }
  end
end
```

Select it on a product with
`fulfillment_config.plugin_provider = "<plugin-id>:<key>"`; optional
`fulfillment_config.provider_options` is copied into the allow-listed request.
It is static product configuration: operators must not place credentials,
customer data, or order-derived templates in it. The frozen request contains
`schema_version`, `provider_id`, stable
`delivery_id`, `attempt` (`number` and `idempotency_key`), safe order totals and
status, safe item/product/variant identifiers and amounts, and `options`. It
contains no host-injected user identity, address, payment data, provider
credential, or arbitrary order metadata.

The provider must use `delivery_id` (or the supplied attempt idempotency key) to
deduplicate external work. It must return only:

```ruby
{ status: "succeeded", external_reference: "..." }
{ status: "retryable", error_code: "provider_timeout" }
{ status: "failed", error_code: "invalid_destination" }
```

`status` is exactly `succeeded`, `retryable`, or `failed`;
`external_reference` is an optional string of at most 200 characters; failed
results require a normalized `error_code`. Extra keys, invalid results, missing
or disabled providers, and handler exceptions are converted into safe
fulfillment failures without exposing the exception to the customer. Declare
`commerce.fulfillments.write`.

Declare the matching `<domain>.events.read` capability for every event domain a
plugin consumes—for example `commerce.events.read` for the catalog above and
`forum.events.read` for forum events. A missing declaration produces an
`undeclared_capability` warning but does not block registration or delivery
because deployment plugins are fully trusted.

## Synchronous service filters

Events observe work after a core action. When a plugin needs to extend an input
before core validation and persistence, register a synchronous filter instead
of prepending or monkey-patching a Rails service:

```ruby
Mcweb::Plugins.register do |plugin|
  plugin.filter("forum.topic.create.attributes", priority: 50) do |attributes, context|
    section_id = context.dig("section", "id")
    next attributes unless section_id == 12

    attributes.merge(
      "title" => "[Support] #{attributes.fetch('title')}"
    )
  end

  plugin.filter("forum.post.create.attributes") do |attributes|
    attributes.merge(
      "body" => "#{attributes.fetch('body')}\n\n_Processed by Acme_"
    )
  end
end
```

The stable v1 filter points are:

| Filter | Mutable value keys | Context |
| --- | --- | --- |
| `forum.topic.create.attributes` | `title`, `body`, `tag_names`, `prefix`, `custom_fields` | `user`, `section` identity snapshots |
| `forum.post.create.attributes` | `body`, `whisper` | `user`, `topic` identity snapshots |
| `forum.topic.edit.attributes` | values plus `*_provided` flags for `title`, `tag_names`, `prefix`, `poll_params`, `custom_fields` | `user`, `topic` identity snapshots |
| `forum.post.edit.attributes` | `body`, `reason` | `user`, `post`, `topic` identity snapshots |

Values and contexts are deeply normalized and frozen before each callback.
Active Record objects become identity-only snapshots, exactly like event data.
The callback must return the next value with the same root type. A raised
exception or incompatible return value is diagnosed and skipped; later filters
still run. Recursive application of the same filter is bounded and diagnosed.
Ordering is priority, plugin ID, then declaration order. Filters are synchronous,
so expensive or retryable side effects still belong in an event listener and
background job.

Declare `forum.extend` when registering forum filters. Capabilities remain
compatibility and audit metadata for fully trusted deployment code rather than
a sandbox boundary.

## Around-service decorators

Use an around-service decorator when a trusted plugin must wrap a complete core
operation rather than only transform its input:

```ruby
Mcweb::Plugins.register do |plugin|
  plugin.decorate_service("forum.topic.create", priority: 50) do |proceed, input, context|
    result = proceed.call(
      input.merge("title" => "[Support] #{input.fetch('title')}")
    )
    result
  end
end

Mcweb::Plugins.call_service(
  "forum.topic.create",
  input: topic_attributes,
  context: { user: current_user, section: section }
) do |input, context|
  Community::CreateTopic.call(
    user: User.find(context.dig("user", "id")),
    section: Community::Section.find(context.dig("section", "id")),
    **input.symbolize_keys
  )
end
```

The host explicitly defines each stable service boundary with
`Mcweb::Plugins.call_service`; registering a decorator does not monkey-patch
arbitrary Ruby classes. Decorators run by priority, plugin ID, then declaration
order. Inputs and contexts are deeply normalized and frozen. A replacement
input must preserve the original root kind.

The continuation is memoized and thread-safe. The downstream operation runs
exactly once even if a plugin calls `proceed` repeatedly, raises before or after
continuing, or forgets to continue. Plugin failures are diagnosed and isolated;
an exception from the core operation is propagated unchanged and is not
attributed to a plugin. Recursive decoration of the same service is bypassed
and diagnosed, including when the continuation runs on a worker thread.

Service results stay host-native so Active Record objects and `ServiceResult`
instances retain identity and behavior. A decorator may return a replacement
result only when it preserves the downstream root kind or class. Declare the
matching `<domain>.extend` capability, such as `forum.extend`, for capability
auditing.

The stable forum service decorator boundaries are:

| Service | Input keys | Context |
| --- | --- | --- |
| `forum.topic.create` | `title`, `body`, `tag_names`, `prefix`, `custom_fields` | `user`, `section` identity snapshots |
| `forum.post.create` | `body`, `whisper` | `user`, `topic` identity snapshots |
| `forum.topic.edit` | values plus the `*_provided` flags for `title`, `tag_names`, `prefix`, `poll_params`, `custom_fields` | `user`, `topic` identity snapshots |
| `forum.post.edit` | `body`, `reason` | `user`, `post`, `topic` identity snapshots |

These use the same field and context contracts as the matching synchronous
filters. All four require the compatibility/audit capability `forum.extend`.

## Versioned host API

Every v1 definition exposes one reusable facade through `plugin.api`:

```ruby
Mcweb::Plugins.register do |plugin|
  api = plugin.api

  plugin.on("identity.user.registered") do |event|
    user = User.find(event.data.dig("user", "id"))
    topics = api.forum.topics(user:, section_slug: "announcements", limit: 10)
    Rails.logger.info(topics.value) if topics.success?
  end
end
```

`api.api_version` is `"1"`. The facade is split into `api.commerce`,
`api.forum`, `api.events`, `api.identity`, `api.jobs`, `api.site`, and
`api.settings`.
Every operation returns a frozen
`Mcweb::PluginApi::V1::Result`:

```ruby
{
  schema_version: "1",
  success: true,
  code: "ok",
  value: "...",
  error: nil,
  errors: {}
}
```

Use `success?` and `failure?`; failure codes currently include
`invalid_argument`, `invalid_user`, `not_found`, `service_failure`, and
`event_publish_failed`. Settings additionally return explicit codes such as
`settings_not_declared`, `migration_required`, `schema_digest_mismatch`, and
`revision_conflict`. Jobs additionally return codes such as
`jobs_not_declared`, `job_not_declared`, `idempotency_conflict`,
`incompatible_job`, and `invalid_job_state`. An unexpected database,
feature/settings backend, queue adapter, audit hook, or serializer exception
becomes a fixed `host_error` instead of escaping the facade. Values, validation
errors, and nested collections are owned and deeply frozen by the SDK. No
result contains an Active Record model.

### User-bound forum reads

```ruby
category = api.forum.find_category(user:, slug: "community")
categories = api.forum.categories(user:, limit: 50)

section = api.forum.find_section(user:, slug: "general")
sections = api.forum.sections(user:, limit: 50)

tag = api.forum.find_tag(user:, slug: "introductions")
tags = api.forum.tags(user:, query: "intro", limit: 25)

topic = api.forum.find_topic(user:, public_id: "topic_...")
topics = api.forum.topics(user:, section_id: 12, limit: 50)

post = api.forum.find_post(user:, id: 9001)
posts = api.forum.posts(user:, topic_public_id: "topic_...", limit: 100)

topic_matches = api.forum.search_topics(
  user:,
  query: "release notes",
  category_slug: "community",
  section_slug: "announcements",
  tag_slug: "releases",
  author: "alice",
  sort: "relevance",
  limit: 25
)
post_matches = api.forum.search_posts(
  user:,
  query: "upgrade steps",
  tag_slug: "releases",
  sort: "recent",
  limit: 25
)
```

`user: nil` performs an anonymous read. A non-nil reader must be a persisted
`User`. Section reads always use `Community::SectionAccess`; topic and post
reads always use both its section scope and the complete
`Community::ForumAccess` predicate. Consequently login-only and permission-only
sections, hidden or draft topics, pending posts, and staff whispers are omitted
unless that exact user may read them. A published unlisted topic remains
direct-readable because that is the canonical web policy. An inaccessible ID
returns the same `not_found` result as a missing ID.

Forum values are explicit v1 snapshots with allow-listed fields. Section
snapshots include identity, hierarchy, name/slug and read-only/login flags.
Topic snapshots include identity, section/author IDs, title/state and counters.
Post snapshots include identity, topic/author IDs, reply linkage, body and
state. Adding a database column does not automatically add it to the SDK.

Category catalogs include only categories with at least one section visible to
that reader, so a category containing only permission-restricted sections is
not disclosed. Tag catalogs exclude aliases and return only canonical tags
usable by the reader; `find_tag` accepts an alias but resolves it to its usable
canonical tag. Search uses PostgreSQL full-text matching and the same aggregate
visibility rules as the web search: unlisted or archived topics, whispers,
moderation states, and content in inaccessible sections cannot escape through
results. Search filters are optional, `sort` is `recent`, `oldest`, or
`relevance`, queries are bounded to 500 characters, and all list limits are
bounded to 100. A missing or inaccessible search filter produces an empty
result set rather than disclosing whether the catalog resource exists.

### Forum writes through core services

```ruby
created_topic = api.forum.create_topic(
  user:,
  section_slug: "general",
  title: "Hello from a reviewed plugin",
  body: "The normal forum policy still applies.",
  tag_names: ["introductions"],
  ip_address: request.remote_ip
)

if created_topic.success?
  created_post = api.forum.create_post(
    user:,
    topic_id: created_topic.value.fetch("id"),
    body: "A normal reply",
    quoted_post_id: 42,
    ip_address: request.remote_ip
  )
end
```

These methods resolve the target with the same user-bound read policy and then
delegate to `Community::CreateTopic` or `Community::CreatePost`. Permission,
trust level, read-only section, moderation approval, warning, spam, rate-limit,
IP-ban, attachment and side-effect behavior therefore remains core-owned.
The facade intentionally does not expose `skip_interval_check` or staff-whisper
options. A core `ServiceResult` failure becomes an immutable v1 result with
code `service_failure`; a successful model becomes an allow-listed snapshot.

Existing topics and posts can be edited through the same core policies:

```ruby
edited_topic = api.forum.edit_topic(
  user:,
  topic_public_id: "topic_...",
  title: "Updated title",
  tag_names: ["releases", "documentation"],
  prefix: "Guide",
  custom_fields: { "release_version" => "2.0" }
)

edited_post = api.forum.edit_post(
  user:,
  id: 9001,
  body: "Updated body",
  expected_revision: current_post.fetch("revision"),
  reason: "Corrected the upgrade step",
  attachment_ids: [123, 124]
)
```

`edit_topic` delegates to `Community::EditTopic` and requires at least one
provided attribute. `edit_post` delegates to `Community::EditPost` and requires
the latest post snapshot `revision`; a stale revision fails without changing the
post or its attachments. Ownership,
moderator permissions, edit windows, archived/read-only behavior, censorship,
mentions, hashtags, attachments, revisions, notifications, events, and
real-time invalidation remain core-owned.

### Reactions, bookmarks, and subscriptions

Reaction catalogs and summaries are stable snapshots rather than model
instances:

```ruby
types = api.forum.reaction_types(user:)
summary = api.forum.post_reactions(user:, id: 9001)
reaction = api.forum.toggle_reaction(user:, post_id: 9001, emoji: "👍")
```

`toggle_reaction` delegates to `Community::ToggleReaction`, preserving the
configured reaction catalog, own-post rule, trust level, daily limit, cooldown,
points, notification, event, and real-time side effects. Its result contains
`added`, the selected emoji, and current counts. Anonymous users can read the
catalog and visible-post summaries but cannot mutate them.

Bookmark operations use explicit desired state and are idempotent:

```ruby
state = api.forum.topic_bookmark(user:, topic_public_id: "topic_...")
api.forum.bookmark_topic(user:, topic_public_id: "topic_...")
api.forum.unbookmark_topic(user:, topic_public_id: "topic_...")

post_state = api.forum.post_bookmark(user:, post_id: 9001)
api.forum.bookmark_post(user:, post_id: 9001)
api.forum.unbookmark_post(user:, post_id: 9001)

# Equivalent lower-level forms:
api.forum.set_topic_bookmark(user:, topic_id: 42, bookmarked: true)
api.forum.set_post_bookmark(user:, post_id: 9001, bookmarked: false)
```

Calling `bookmark_*` twice leaves one bookmark; calling `unbookmark_*` twice
leaves none. Targets are resolved through the reader's canonical topic/post
policy before the existing toggle service runs.

Topic, section, and tag subscriptions support every core notification level
(`watching`, `tracking`, and `normal`) plus explicit `off`:

```ruby
api.forum.subscribe_topic(user:, topic_id: 42, level: "tracking")
api.forum.unsubscribe_topic(user:, topic_id: 42)
api.forum.topic_subscription(user:, topic_id: 42)

api.forum.subscribe_section(user:, section_slug: "announcements", level: "normal")
api.forum.unsubscribe_section(user:, section_slug: "announcements")
api.forum.section_subscription(user:, section_slug: "announcements")

api.forum.subscribe_tag(user:, tag_slug: "releases")
api.forum.unsubscribe_tag(user:, tag_slug: "releases")
api.forum.tag_subscription(user:, tag_slug: "releases")
```

The corresponding `set_topic_subscription`, `set_section_subscription`, and
`set_tag_subscription` methods accept an explicit `level`. All use
`Community::SetSubscriptionLevel`, are idempotent, require a persisted user,
and refuse resources that are not currently visible or usable by that user.
Mutation methods audit `forum.write`; catalogs, searches, summaries, and state
reads audit `forum.read`.

### Topic lifecycle and moderation

High-value XenForo-style lifecycle operations are exposed only where McWeb has
a mature core service:

```ruby
moved = api.forum.move_topic(
  user: moderator,
  topic_public_id: "topic_...",
  section_slug: "support",
  leave_redirect: true
)
copied = api.forum.copy_topic(
  user: moderator,
  topic_id: 42,
  section_id: 8
)
merged = api.forum.merge_topics(
  user: moderator,
  source_topic_id: 42,
  target_topic_public_id: "topic_target"
)
split = api.forum.split_topic(
  user: moderator,
  topic_id: 42,
  post_id: 9001,
  title: "New topic",
  section_slug: "support"
)
```

These methods first resolve every source and target through the acting user's
current `ForumAccess`/`SectionAccess`, then delegate to `MoveTopic`,
`CopyTopic`, `MergeTopics`, or `SplitTopic`. The core service still owns
moderator scope, post floor reassignment, redirect stubs, counters, fields,
tags, audit entries, events, and real-time invalidation. Permission revocation
therefore closes both source and destination before the service is invoked.

Post lifecycle and allow-listed moderation actions use the same pattern:

```ruby
api.forum.delete_post(user:, id: 9001)
api.forum.restore_post(user: moderator, id: 9001)
api.forum.approve_post(user: moderator, id: 9002)
api.forum.reject_post(user: moderator, id: 9003, reason: "Policy")

api.forum.moderate_topic(
  user: moderator,
  topic_id: 42,
  action: "lock",
  lock_reason: "Review"
)
api.forum.moderate_post(
  user: moderator,
  id: 9001,
  action: "set_staff_notice",
  staff_notice: "Verified answer"
)
```

Topic actions are `lock`, `unlock`, `pin`, `unpin`, `bump`, `hide`, `unhide`,
`feature`, `unfeature`, `enable_wiki`, `disable_wiki`,
`global_announcement`, `remove_global_announcement`, `unlist`, `list`,
`archive`, `unarchive`, `assign`, and `unassign`. Post actions are `hide`,
`unhide`, `enable_wiki`, `disable_wiki`, `set_staff_notice`,
`clear_staff_notice`, and `change_author`. Unknown actions fail at the SDK
boundary; the core service performs the final global/section moderator check.
These operations audit `forum.moderate`.

Solution, collaboration, and fine-grained moderation services are also
available without exposing model mutation:

```ruby
api.forum.mark_topic_solved(
  user: topic_author,
  topic_id: 42,
  post_id: 9001
)
api.forum.unsolve_topic(user: topic_author, topic_id: 42)

api.forum.invite_topic_watcher(
  user: topic_author,
  topic_id: 42,
  username: "helper"
)
api.forum.create_topic_staff_note(
  user: moderator,
  topic_id: 42,
  body: "Escalated for review"
)

api.forum.ban_topic_reply(
  user: moderator,
  topic_id: 42,
  target_username: "member",
  reason: "Cooling-off period",
  expires_at: 1.day.from_now.iso8601
)
api.forum.unban_topic_reply(
  user: moderator,
  topic_id: 42,
  target_username: "member"
)
```

Every operation delegates to its matching core service. Topic ownership,
global/section moderation, visibility, duplicate invites, notifications,
accepted-answer points, reply-ban enforcement, and future expiry validation
therefore remain identical to the web flow. User targets require exactly one
positive ID or exact case-insensitive username.

McWeb currently has no dedicated core topic soft-delete or topic-restore
service. SDK v1 deliberately does not emulate those operations with direct
model updates; hiding/unhiding is available through `moderate_topic`.

### Polls and topic custom fields

Poll results preserve the web privacy rule for
`hide_results_until_vote`: an open poll omits counts until that user has voted.
Anonymous polls never expose voter identities through this facade.

```ruby
poll = api.forum.find_poll(user:, id: 17)
poll = api.forum.topic_poll(user:, topic_public_id: "topic_...")
voted = api.forum.vote_poll(user:, id: 17, option_indices: [0, 2])
revoked = api.forum.revoke_poll_vote(user:, id: 17)
closed = api.forum.close_poll(user: topic_author, id: 17)
```

Voting, revocation, and closing delegate respectively to `VotePoll`,
`RevokePollVote`, and `ClosePoll`, retaining section visibility, trust,
read-only, lock, reply-ban, option-count, ownership, notification, small-action,
and real-time rules. Poll reads audit `forum.read`; mutations audit
`forum.write`.

Active topic field definitions and values are read using the same applicability
and display serialization as the web:

```ruby
definitions = api.forum.topic_field_definitions(
  user:,
  section_slug: "support"
)
fields = api.forum.topic_fields(user:, topic_id: 42)
# topic_custom_fields is the descriptive alias for topic_fields
```

Definition snapshots include key, label, type, choices, required/display
settings, owner plugin ID, and whether the current user may edit the field.
Topic field snapshots include raw and display values only after the topic has
passed current read policy. Updating values remains part of `edit_topic`, which
delegates to `SyncTopicFieldValues`.

### Attachment metadata and lifecycle

The SDK exposes allow-listed metadata only: filename, content type, byte size,
download count, owner/post IDs, and timestamps. It never returns Active Storage
keys, checksums, signed URLs, blobs, or file contents.

```ruby
uploaded = api.forum.create_attachment(user:, file: uploaded_file)
unlinked = api.forum.unlinked_attachments(user:, limit: 25)

linked = api.forum.sync_post_attachments(
  user:,
  post_id: 9001,
  attachment_ids: [uploaded.value.fetch("id")]
)

attachment = api.forum.find_attachment(user:, id: uploaded.value.fetch("id"))
attachments = api.forum.post_attachments(user:, post_id: 9001, limit: 50)
```

Creation delegates to `CreatePostAttachment`; linking and unlinking delegate to
`SyncPostAttachments`. Upload trust level, allowed type, size, filename,
ownership, edit window, moderator scope, archived topic, and post visibility
remain core-owned. An unlinked upload is visible only to its owner. Once linked,
every metadata read rechecks `PostAttachmentAccess`; revoking private-section
permission immediately hides it. SDK v1 provides no delete operation because
there is no dedicated authorized attachment-delete service.

### Event and site reads

```ruby
catalog = api.events.catalog
published = api.events.publish(
  "acme.demo.completed",
  topic_id: created_topic.value.fetch("id")
)

features = api.site.features
forum_enabled = api.site.feature("forum")
setting = api.site.setting("forum.new_topic_window_days", default: "14")
```

The event catalog is the documented `Mcweb::Events::CATALOG`. Publishing accepts
any valid namespaced event for forward-compatible, plugin-owned events; normal
listeners still receive the immutable v1 event DTO. Site feature values delegate
to `FeatureFlags`. Setting access delegates to `SiteSetting.get` for one exact
key and has no set/unset API. Settings can contain operational secrets, so a
reviewed plugin should request only keys it needs and must not log their values.

Recommended declarations are `forum.read`, `forum.write`, `forum.moderate`,
`forum.events.read`, `forum.events.publish`, `site.features.read`, and
`site.settings.read`. A commerce event consumer/provider normally declares
`commerce.events.read` and `commerce.fulfillments.write`. The first undeclared
runtime use of each facade capability records an `undeclared_capability`
diagnostic. It is still allowed: capability metadata is an audit/compatibility
signal, never a security boundary.

## Lifecycle and operations

The Rails initializer reloads deployment plugins through
`Rails.application.config.to_prepare`. Reload first unsubscribes every central
event subscription, clears registrations, reloads entrypoints, validates the
dependency graph, and subscribes once per event. Repeated reloads therefore do
not duplicate event delivery. Concurrent lifecycle calls are serialized so one
process cannot interleave two partial generations. In development, an existing
plugin root is registered as a Rails watchable directory for `.rb`, `.yml`, and
`.yaml` changes, allowing those changes to trigger the normal reloader.

Discovered dependency entrypoints load before dependants. If a discovered
required dependency fails while loading, the dependant entrypoint is not
executed, so its top-level side effects cannot run against a partial dependency.
An inert definition is retained for the dependant, a
`dependency_load_failed` load diagnostic is recorded, and normal boot
dependency checks mark it disabled. A dependency absent from discovery keeps
the existing behavior: the dependant registers and boot reports
`missing_dependency`.

Set `MCWEB_DISABLE_PLUGINS=1` as an emergency switch. Entrypoints are not
evaluated and no plugin listeners are activated. Restart or reload each Rails
process after changing plugin files or environment configuration in production;
every process owns its own registry.

The admin/backend layer can read immutable snapshots without accessing registry
internals:

```ruby
Mcweb::Plugins.list
# [{ id:, name:, version:, status:, listener_count:, filter_count:,
#    service_decorator_count:, failure_count:, last_error:, activation_order:, ... }]

Mcweb::Plugins.diagnostics
# [{ level:, code:, phase:, plugin_id:, event:, message:, exception:,
#    occurred_at: }]
```

Useful statuses are `registered`, `active`, `degraded`, and `disabled`.
Diagnostics cover load, dependency activation, capability audit, subscription,
normalization, and listener failures. Each process retains the newest 1,000
diagnostics, with messages bounded to 4,096 characters. `Mcweb::Plugins.reload!`,
`boot!`, and `reset!` are available for deployment tooling and tests.

SDK v1 provides the trusted host facade above plus an admin package manager.
An administrator with `system.plugins.manage` can upload a reviewed local ZIP
with a mandatory lowercase SHA-256, install or explicitly upgrade it, enable or
disable it, and uninstall it into the recoverable quarantine. The manager keeps
an operation journal, blocks unsafe dependency transitions, and rolls filesystem
and runtime state back when activation fails.

Marketplace packages may declare a package-local setup file:

```yaml
setup: db/setup.rb
```

```ruby
Mcweb::Plugins::Marketplace::Setup.define do
  install_step("create_schema") { |context| create_schema(context.connection) }
  upgrade_step("add_slug", to: "1.2.0") { |context| add_slug(context.connection) }
  uninstall_step("drop_schema") { |context| drop_schema(context.connection) }
end
```

One file registers exactly one plan. Step IDs are unique across install,
upgrade, and uninstall; install/uninstall use declaration order, while upgrades
use target SemVer then declaration order. The Manager executes install only for
a fresh install, upgrade only for targets between the installed and candidate
versions, and uninstall only for uninstall. Disable and enable never invoke
setup code. `teardown_step` is an alias for `uninstall_step`.

Setup database work, runtime reload, receipt persistence, and filesystem
activation share one coordinated failure boundary. Setup callbacks run inside a
new Active Record transaction and receive its connection. Any callback failure
rolls that transaction back, restores the prior package/runtime/receipt, and
records only a bounded error class plus validated phase/step ID. Completed
versions and step IDs live in the receipt, so a retried step is skipped.

Setup remains reviewed, fully trusted Ruby rather than a sandbox. Paths and DSL
shape are constrained to prevent client-selected files and malformed plans;
external side effects or work deliberately performed on another connection
cannot be rolled back and must be designed idempotently.
