# Core SiteSetting governance

## Ownership

Highest reusable owner: **CE**.

The `SiteSetting` table, the common administrator settings hub, audit rules, and
the configuration primitives are shared by every edition. EE and EE-PVP may
register downstream namespaces and keys during startup, but must not copy or
replace the CE registry.

## Problem statement

The common System Settings form previously inferred types and sensitivity from
key names and allowed every stored key that was not manually protected. Core
namespaces were not registered at startup, so a forum, store, Minecraft,
template, security, or operational setting could appear in the generic form and
bypass its purpose-built controller. Webhook secrets were also returned by the
forum and store settings pages.

## Static ownership inventory

| Namespace | Current CE keys or patterns | Owning surface |
| --- | --- | --- |
| `general.*`, `site.*` | `general.site_name`, `site.name`, `site.url` | Admin System Settings basic form |
| `features.*` | Forum, Store, Website Blog, Minecraft enablement | Admin System Feature Toggles |
| `frontend.*` | Active website/portal template IDs | Admin Frontend Templates |
| `forum.*` | moderation limits, trust thresholds, points, reactions, signatures, PM limits, upload/attachment controls, saved-search and event webhooks, VAPID keys, online peak state | Admin Forum Settings; Admin Forum Points; internal forum runtime for VAPID/peak state |
| `store.*` | storefront toggles, checkout limits, shipping, SEO, refund timing, webhook delivery, tax snapshot defaults | Admin Store Settings and its feature controls |
| `minecraft.*` | linking copy, profile display, bridges, graceful stop, command allow-list, backup, primary-account policy, permission mappings | Admin Minecraft Settings; Permission Group Mappings |
| `security.*` | `security.rate_limits.<action>.<dimension>_{limit,window_seconds}` | Admin System Rate Limits |
| `webhook.*` | failure thresholds, alert recipient/locale/cooldown, last-alert timestamp | Admin Forum Settings for policy; internal alert worker for timestamp |
| `integrations.*` | reserved for host-managed external integrations | Dedicated integration controllers only |
| `identity.*` | reserved for identity-owned configuration | Dedicated Identity/Security controllers only |
| `operations.*` | reserved for job/runtime-owned configuration | Internal operations services only |
| `api.*` | legacy API request limit | Admin System Rate Limits |
| `website.*` | CMS recovery retention | Website content lifecycle / CMS administration |

Unregistered keys inside any namespace in this table are intentionally treated
as core-but-unknown. The generic form must hide them and reject forged writes.
An unregistered non-core key remains a legacy custom string setting so existing
extensions are not broken; plugin settings continue to use their schema-managed
plugin store.

## Functional requirements

- Register every core namespace during boot with one owner and one allowed
  surface: basic, dedicated, or internal.
- Register current core keys with their storage type, sensitivity, writeability,
  and portable constraints.
- Resolve the longest matching namespace and reject conflicting startup
  registrations.
- Allow the common form to show and update only explicit generic keys plus
  legacy non-core custom keys.
- Allow the basic form to keep updating site name and site URL.
- Reject a mixed forged request atomically if any submitted key belongs to a
  core, dedicated, internal, read-only, or wrong-owner surface.
- Normalize booleans and integers strictly; validate URL, email, enum, locale,
  JSON, timestamp, length, and numeric ranges before persistence.
- Return localized Chinese or English validation messages without echoing the
  rejected value.
- Never serialize secret/confidential values. A dedicated form receives only an
  empty value and `configured=true`; an empty submission preserves the existing
  secret.
- Audit only changed key names and ownership metadata for configuration writes
  and rejections. Secret values must never enter audit metadata, before/after
  state, flash messages, or exception messages.
- Downstream editions may append namespace/key registrations but cannot change
  an existing CE owner, surface, type, or sensitivity.

## Implementation checklist

- [x] Extend the CE namespace registry with setting schemas and validation.
- [x] Add boot-time CE namespace and key registrations.
- [x] Make the generic System Settings controller fail closed for registered
  namespaces and use registry-provided type/sensitivity metadata.
- [x] Redact and preserve secrets on Forum and Store settings pages.
- [x] Route Forum, Store, and Minecraft settings writes through registered type
  validation.
- [x] Add independent Chinese and English validation messages.
- [x] Add focused contract/integration test source.
- [ ] Run registry, controller, locale, and browser verification in the shared
  CNB validation batch.
- [ ] Visually confirm generic, Forum, Store, and Minecraft forms in local Edge.

## Deferred validation matrix

The later CNB batch must cover boot conflicts, longest-prefix ownership,
unknown-core rejection, mixed-request atomicity, integer/boolean/URL/JSON
failures, both locales, read-only state, secret non-serialization, blank-secret
preservation, and audit payload redaction. Local Edge acceptance must inspect
both configured and unconfigured password fields and confirm the generic page no
longer lists dedicated keys.
