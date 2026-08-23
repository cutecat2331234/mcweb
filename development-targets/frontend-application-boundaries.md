# Frontend application boundaries

## Ownership decision

- Owner: CE.
- Reason: application identity, Inertia transport rules, page resolution, shared bootstrap behavior, document-navigation safety, resource isolation, and downstream registration are edition-neutral platform contracts. They must be implemented once in CE and inherited through ordinary `CE -> EE -> EE-PVP` merges.
- Downstream rule: EE may later register Channel and EE-PVP may later register player PVP through the CE extension contract. This CE task does not add either adapter and must not copy, cherry-pick, squash, rebase, or recreate downstream work.
- UI rule: Forum, Store, Account, Staff, Admin, and the Website Preview projection continue to use the existing McWeb UI library and tokens. This task does not introduce another UI system or implement a downstream Astro design.

## Final page/runtime ownership table

| Application id | Runtime owner | Renderer / entry contract | Positive page ownership | Primary page routes |
| --- | --- | --- | --- | --- |
| `website` | CE | `ce_inertia_document`: a dedicated transitional Website document renderer. It resolves only the initial server-selected `Website/**` or `Plugins/**` component and forces every Website navigation through a new document. It is neither the umbrella entry nor Website Preview. | CE owns `Website/**` and public `Plugins/**`. Public plugin navigation belongs here; Admin plugin management stays Admin. | `/`, `/signed-out`, `/blog/**`, `/plugins/**`, and validated public CMS slugs. |
| `forum` | CE | `forum` Inertia entry with a positive `Community/**` resolver after privileged moderation pages move to Staff. | CE owns public community, conversations, reporter cases/appeals, saved drafts, and the public staff directory. | GET `inertia_page` routes below `/app/forum/**`. |
| `store` | CE | `store` Inertia entry with positive `Commerce/**` and `Payments/**` resolvers. | CE owns Commerce and Payments user journeys. | GET `inertia_page` routes below `/app/store/**` and `/app/payments/**`. |
| `account` | CE | `account` Inertia entry with positive `Account/**`, `Identity/**`, and `Minecraft/**` resolvers. | CE owns account center, identity/security/session pages, and Minecraft account linking. | GET `inertia_page` routes below `/app/account/**`, `/app/identity/**`, and `/app/minecraft/**`. |
| `staff` | CE | `staff` Inertia entry with the CE `Staff/**` base resolver plus validated downstream positive contributions. | CE owns the Staff workspace and Forum staff moderation. Downstream products own only their contributed Staff pages. | `/app/staff/**`; PVP later contributes `/app/staff/pvp/**`. |
| `admin` | CE | `admin` Inertia entry with the CE `Admin/**` base resolver plus validated downstream positive contributions. | CE owns Admin platform pages. EE owns `Admin/Chat/**`; EE-PVP owns `Admin/Pvp/**`, each running inside the Admin application. | `/admin/**`, excluding explicit Website Preview routes; PVP later contributes `/admin/pvp/**`. |
| `website_preview` | CE auxiliary | `website-preview` Inertia entry. Its library-based preview shell may project only Website-owned page components; the inner canvas uses the real Website layout/styles. | No product ownership. Explicit projections of `Website/**` and `Plugins/**` only. | Exact Admin page/article/template preview GET routes, matched before Admin. |
| `channel` | EE | Downstream `channel` Inertia entry and adapter added only after the ordinary CE -> EE merge. | EE owns `Ee/**`; Admin Channel pages remain EE-owned `Admin/Chat/**` contributions to Admin. | `/app/chat/**`, `/app/channels/**`, `/app/chat/messages/:message_id`, and registered Channel message deep links. EE contributes Channel as the `/app` landing target. |
| `pvp` | EE-PVP | Downstream `pvp` Inertia entry for player/tester pages; Staff/Admin pages augment the CE entries. The completely self-written Astro Website renderer is a separate Website renderer contribution and imports no APP UI. | EE-PVP owns `Pvp/**`, `Pvp/Staff/**`, and `Admin/Pvp/**`; every page has one product owner and one runtime application. | `/app/pvp/**` including Tester, `/app/staff/pvp/**`, and `/admin/pvp/**`. |

The old non-Admin umbrella entry remains until the dedicated CE Website document renderer and all CE Inertia entries are wired. It is removed only after a static render inventory proves every existing controller/component pair has a real renderer.

## Final route-kind and method table

| Route kind | Allowed methods | Client contract | Server boundary behavior | Required examples |
| --- | --- | --- | --- | --- |
| `inertia_page` | GET/HEAD only | Same-origin and same-application GET may use Inertia. Cross-application GET uses native document navigation. Never prefetch a different application. | Missing/unknown/mismatched application signal returns `409` + validated GET `X-Inertia-Location`; matching requests continue through normal authorization. | Forum, Store, Account, Staff, Admin, Channel, and PVP page routes. |
| `application_action` | POST/PUT/PATCH/DELETE | Not a navigation target or prefetch target. Same-application Inertia form mutation is allowed; the response returns or redirects to an owned GET page. | Source application must match the route owner. A cross-app non-GET is rejected before callbacks and may reload only a validated safe GET referer/application landing, never the original mutation URL. | Forum writes, Store cart/checkout actions, Account profile/security actions, Staff/Admin mutations. |
| `document` | GET/HEAD only | Always native document navigation. | Never converted into an Inertia component response. | CE Website renderer, `/app` launcher/redirect, setup/health documents, legacy redirects. |
| `download` | GET/HEAD only | Native anchor/form; no Inertia interception or prefetch. | Preserve content disposition/streaming and authorization without an application redirect. | Forum attachment/RSS/OPML/sitemap, Store image/RSS/sitemap/PDF/download, Account export download, Admin exports. |
| `api` | Declared per route | Explicit `fetch`/XHR client with its documented response type; no Inertia navigation semantics. | Existing authentication/authorization/CSRF/CORS contract applies; the application header is telemetry/consistency only. | JSON APIs, upload status, connector/node endpoints, realtime/event endpoints. |
| `shared_action` | Explicit non-GET methods only | Same-origin CSRF-protected fetch or native form, never Inertia navigation. Descriptor lists allowed source applications and a safe GET completion/failure location. | Guard validates method, origin/CSRF through Rails, allowed source application, and safe redirect. Header never grants permission. | `/locale`, sign-out, `/app/evidence/**` create/discard operations, and developer persona switching. |

Route rules are ordered and method-aware. Format/endpoint exceptions win before broad path rules. In particular, Forum RSS/OPML/sitemap and attachments, Store image/RSS/sitemap/PDF/download routes, and Account export downloads can never be classified by their surrounding application page prefix.

## Final downstream augmentation table

| Contribution | Declared by | Extends / creates | Positive additions | Non-negotiable validation |
| --- | --- | --- | --- | --- |
| CE base descriptors | CE | Creates Website, Forum, Store, Account, Staff, Admin, Website Preview | CE routes, entries, page prefixes, styles, locales, UI adapter, error and budget fixtures | Immutable downstream; duplicate ids/prefixes/routes fail closed. |
| Channel application | EE | Creates `channel` | `/app/chat/**`, `/app/channels/**`, message deep links; `Ee/**`; Channel styles/locales/error/budgets; `/app` landing contribution | Must not broaden the CE umbrella or claim CE pages. Existing Channel draft key/version/user isolation and offline recovery are mandatory adapter capabilities. |
| Channel Admin | EE | `extends_application: admin` | Positive `Admin/Chat/**` page loader plus Chat styles/locales/navigation/budgets | Loaded only into Admin's complete manifest closure; EE remains product owner. |
| PVP player/tester | EE-PVP | Creates `pvp` | `/app/pvp/**`; positive `Pvp/**` loader including Tester; PVP APP styles/locales/error/budgets | Must use `@mcweb/ui` or a registered APP adapter. |
| PVP Staff | EE-PVP | `extends_application: staff` | `/app/staff/pvp/**`; positive `Pvp/Staff/**` loader and PVP Staff resources | Cannot modify CE Staff descriptor or claim `Staff/**`. |
| PVP Admin | EE-PVP | `extends_application: admin` | `/admin/pvp/**`; positive `Admin/Pvp/**` loader and PVP Admin resources | Cannot modify CE Admin descriptor or claim another product prefix. |
| PVP Website renderer | EE-PVP | `extends_application: website`, exclusive `renderer_adapter` | Completely self-written Astro Website build/routes/styles/locales/budgets | Replaces the CE transitional renderer only in EE-PVP; cannot import APP UI or use Website Preview as renderer. |

Base and contribution manifests are discovered from separate directories. Executable adapter modules self-register through a CE-owned discovery glob and contain literal positive `import.meta.glob` expressions, allowing downstream additions without editing a CE descriptor or entry. Validation tracks product owner separately from runtime application and rejects multiple owners, multiple runtimes, negative page globs, route/method conflicts, unregistered resources, or more than one exclusive Website renderer.

## Architecture contracts

### Declarative registry

- Store immutable CE base descriptors under `config/frontend_applications/base/` and downstream contribution manifests under `config/frontend_applications/contributions/`. Ruby and TypeScript consume the same canonical manifest data; there are no independent hand-maintained registries.
- A base descriptor declares the stable id, product owner, runtime owner, runtime kind, ordered method-aware route rules, positive component prefixes/projections, entrypoint or renderer adapter, shell adapter, UI adapter, styles, locale domains, error identity, and budget fixtures.
- A contribution either creates one downstream application or names `extends_application`. It may add only literal positive routes, component prefixes, styles, locales, navigation, error, and budget resources owned by its edition. An exclusive Website `renderer_adapter` contribution may replace the CE transitional renderer.
- Executable adapters self-register through CE-owned discovery globs without editing an inherited CE entry. Their literal positive `import.meta.glob` expressions remain statically inspectable.
- Validation fails closed on duplicate ids, owners, runtimes, component prefixes, route/method claims, invalid/unsafe route syntax, negative globs, unknown projections/extensions, missing resources, sibling imports, or competing exclusive renderer adapters.
- Shared JSON/schema data is declarative only. Executable resolvers, imports, CSRF handling, authorization, and security decisions stay in reviewed Ruby/TypeScript code.

### Inertia bootstrap and positive resolution

- Replace duplicated `createInertiaApp` setup with one shared factory that owns CSRF synchronization, locale synchronization, phrase overrides, title policy, intent prefetch, navigation guards, application headers, error capture, and Vue provider installation.
- Keep one thin CE entry per Inertia application: Forum, Store, Account, Staff, Admin, and Website Preview. Add the separate CE Website document entry/renderer, which mounts only the server-selected initial Website component and never establishes Website SPA navigation.
- Every entry declares only positive `import.meta.glob` roots for its allowed namespaces. No entry may use `pages/**/*.vue` plus exclusions, a fallback resolver, or another application's page map.
- A missing or foreign component is a boundary error with the application id and component name; it is never searched in a global page map.
- Validate ownership immediately before every Inertia render as well as during registry boot. A valid application header is a consistency signal, never authorization to render another product's component.
- Remove the old umbrella `entrypoints/inertia.ts` only after a controller/component render inventory proves every CE render has the dedicated Website renderer or one strict Inertia entry. Admin remains a normal consumer of the shared factory rather than a second bootstrap implementation.

### Navigation and server enforcement

- Only a same-origin, same-application GET classified as `inertia_page` uses Inertia and preserves the current document. HEAD may be classified server-side but is never a client navigation target.
- Cross-application page navigation and all `document` routes use native document navigation. The shared router guard cancels attempted cross-app `Link`, `router.visit`, and prefetch operations before an Inertia request and sends the browser to the destination document.
- Plain anchors preserve normal browser behavior for modifier keys, targets, downloads, same-document fragments, external origins, and explicit document navigation.
- `download`, `api`, `application_action`, and `shared_action` routes are never link-intercepted or prefetched. Shared actions use an explicit same-origin CSRF-protected fetch/form adapter; `/locale`, sign-out, `/app/evidence/**`, and developer persona switching declare allowed source applications and safe GET completion locations.
- Every Inertia visit and prefetch sends a stable `X-McWeb-Application` source id in addition to the existing CSRF and validated locale headers.
- Install the server boundary before every callback that may write state, including developer auto-login and `last_seen`. The server independently resolves route kind and destination application; the header neither selects an application nor grants access.
- For a mismatched GET `inertia_page`, preserve flash with `flash.keep`, return `409` plus a same-origin relative validated `X-Inertia-Location` built from the original path/query, set `Cache-Control: no-store`, and merge (not replace) `Vary: X-Inertia, X-McWeb-Application`.
- Reject a mismatched non-GET before controller callbacks. It must never redirect to or replay the original POST/PUT/PATCH/DELETE URL; at most it may expose a validated safe GET referer or application landing for document recovery.
- Registry-unowned routes are never silently absorbed into an application. Ordinary non-Inertia documents/APIs continue through their existing controller contracts; an Inertia request to an unowned destination is forced out of the current SPA.
- Website Preview matchers take precedence over the broader Admin matcher. Public Website and plugin contribution URLs always remain document boundaries.

### Resource, error, and persistence boundaries

- Each application entry imports its own complete application stylesheet and locale-domain set. Shared UI/vendor/tokens may be reused, but an application stylesheet, locale bundle, shell, or page dependency must not import a sibling application's resources.
- Split `PortalLayout`/`usePortalNav` into application shells or inject a validated application navigation adapter. Inventory the complete manifest closure for every entry—including layouts, components, transitive CSS, locales, and contributed adapters—rather than checking resolver globs alone.
- APP/Account/Forum/Store/Staff/Admin base interactions use `@mcweb/ui` or a registered compatibility adapter. No new local Button/Input/Select/Table/Dialog primitive may be added. Website Preview uses the library in its shell, while its canvas loads the real Website styling.
- Split the generated bilingual catalogs into checked application domains while retaining one authoritative Simplified Chinese/English source catalog. Generation and parity checks must prove complete key coverage, matching placeholders, and no cross-application domain leakage.
- Each application has a named error boundary and boot-failure fallback. Failure to resolve or mount one application must not load another application's shell or pages. APP, Staff, and Admin fallbacks use the existing UI library and accessible live/error semantics.
- Performance budgets are computed from the correct application entry plus representative owned pages. A budget calculation must fail if it falls back to the old umbrella entry or includes a sibling entry's initial resources.
- Locale uses a strict allowlist and same-origin cookie/session/user bridge shared by Rails and Astro. Precedence is explicit user change, authenticated preference, validated session/cookie, validated request/header preference, then default; both renderers synchronize changes bidirectionally so a Simplified Chinese selection survives every document transition.
- Theme remains durable through `mc-theme`, with one CSP-compatible first-paint bootstrap contract used before either Rails or Astro paints. Authentication remains in the existing same-origin Rails session.
- Add a shared unsaved-form registry covering same-app Inertia visits, cross-app document navigation, browser back/forward, reload/tab close, successful submit release, and explicit discard. Persisted forum drafts remain server-owned and keep their existing keys. The later Channel adapter must preserve its current draft key/version/user isolation and disconnected recovery semantics.

### Website renderer transition

- CE keeps a real, edition-owned transitional Website renderer for `/`, `/blog/**`, validated CMS slugs, and public Plugins. It uses a dedicated Website document layout/entry, the real Website styles/locales, and strict `Website/**` plus `Plugins/**` resolution.
- Website navigation is always a document transition. Website Preview cannot serve public requests and cannot substitute for this renderer.
- The umbrella entry is removed only after the Website renderer and all six strict CE Inertia entries cover the static render inventory.
- EE-PVP later contributes its own exclusive Astro renderer after ordinary merges. That renderer is fully self-written, does not import APP UI, and does not require any PVP adapter in CE.

## Phased implementation tasks

### Phase 0 — coordination gate

- [x] Inspect the current CE tree and record this target without editing an existing file.
- [x] Receive explicit confirmation that report/appeal work is integrated and CE is frozen at `b385428f3120a2767af2d7329f6fcccc4387d985` with only this plan untracked.
- [x] Re-read `git status` and current `main` before revising the plan.
- [ ] Commit this plan by itself before touching implementation files.
- [ ] Work directly on CE `main`, stage only application-boundary-owned paths, and do not push. Local verification is limited to syntax/format checks, manual static inspection, and `git diff --check`; no local test file, typecheck, build, or application startup may run.

### Phase 1 — canonical registry, route kinds, and augmentation contract

- [ ] Add the shared schema, CE base descriptors, empty downstream contribution directory/contract, Ruby loader, TypeScript loader, executable adapter discovery, and fail-closed validation.
- [ ] Encode ordered method-aware `inertia_page`, `application_action`, `document`, `download`, `api`, and `shared_action` rules with format/endpoint exceptions before broad prefixes.
- [ ] Declare the CE Website, Forum, Store, Account, Staff, Admin, and Website Preview applications plus explicit projections and complete resource/budget metadata.
- [ ] Add static fixtures/tests for Channel and PVP contribution shapes without implementing either adapter.

### Phase 2 — early server guard and render ownership

- [ ] Install the boundary before writable callbacks; resolve the destination from the registry independently of `X-McWeb-Application`.
- [ ] Implement safe GET `409` document recovery with `flash.keep`, `no-store`, merged `Vary`, and validated relative original path/query.
- [ ] Reject cross-app non-GET without replaying its mutation URL; preserve existing authorization/CSRF for allowed application/shared actions.
- [ ] Revalidate component ownership immediately before render and make layouts expose/load only the resolved application entry.
- [ ] Add focused server tests for forged/missing headers, preview precedence, non-GET safety, flash/cache/vary headers, unsafe locations, downloads, APIs, and shared actions for later CNB execution.

### Phase 3 — Website renderer, shared bootstrap, and strict entries

- [ ] Add the CE Website document renderer/layout/entry with positive `Website/**` and `Plugins/**` resolution and real Website resources.
- [ ] Extract the shared Vue/Inertia bootstrap factory and add strict Forum, Store, Account, Staff, Admin, and Website Preview entries with positive globs only.
- [ ] Preserve CSRF, title, phrase override, provider, progress, locale/theme, developer-mode, error, and source-header behavior through explicit factory options.
- [ ] Keep the umbrella only until a static controller/component inventory is fully covered; then remove it and reverse its static contract tests.
- [ ] Add resolver/bootstrap/renderer tests for later CNB execution, including proof that no application resolves a sibling page.

### Phase 4 — route and page ownership correction

- [ ] Move `Community::Moderation::ApprovalsController` and `Community/Moderation/Approvals/Index.vue` to the Staff Forum moderation namespace and `/app/staff/**` route ownership.
- [ ] Keep a document redirect from the old GET URL where compatibility is required; do not retain a second Forum implementation.
- [ ] Move its navigation/deferred-count target into the Staff shell while leaving the public `Community::StaffController` directory in Forum.
- [ ] Keep reporter/appellant Community pages in Forum, Staff review pages in Staff, and administrative review/configuration pages in Admin.
- [ ] Classify public plugin contribution pages/navigation as Website, while `Admin/Plugins/**` and Admin plugin settings remain Admin.
- [ ] Restrict Admin Website preview actions to the Website Preview application and its explicit projected component prefixes.

### Phase 5 — shells, UI, styles, locales, errors, and manifest closure

- [ ] Split `PortalLayout`/`usePortalNav` into application shells or inject registry-validated shell/navigation adapters.
- [ ] Register the existing McWeb UI compatibility adapter, require it or `@mcweb/ui` for base interactions, and prohibit new local Button/Input/Select/Table/Dialog primitives.
- [ ] Add application root styles for Website, Forum, Store, Account, Staff, Admin, and Website Preview; retain only genuinely shared UI/vendor/tokens/foundation in shared styles.
- [ ] Remove application-specific global imports from the shared bootstrap and page layouts.
- [ ] Generate bilingual core/website/forum/store/account/staff/admin locale domains from the authoritative catalogs and make each entry request only its declared domains.
- [ ] Move staff-only moderation copy out of Forum keys while preserving user-facing report/appeal copy in Forum.
- [ ] Add per-application error identities/fallbacks and tests for boot, resolver, and render failures.
- [ ] Extend i18n/style/static checks to reject cross-application imports, incomplete generated catalogs, and incomplete transitive manifest closure across layouts/components/CSS/locales/contributions.

### Phase 6 — navigation, locale/theme, and dirty-form persistence

- [ ] Replace `/app`/`/admin` heuristics with method-aware registry matching in delegated navigation and intent prefetch.
- [ ] Cancel cross-app Inertia visits before network dispatch and use native document navigation; prefetch only reviewed same-app GET `inertia_page` destinations.
- [ ] Preserve modifier-click, target, download, fragment, external-origin, and explicit hard-navigation behavior.
- [ ] Add the strictly validated Rails/Astro locale cookie/session/user bridge with one precedence contract and bidirectional updates.
- [ ] Add the shared CSP-compatible first-paint theme bootstrap and the unsaved-form registry covering Inertia, document, history, reload/close, submit release, and discard.
- [ ] Preserve authenticated session, return destinations, saved Forum draft identity, and the downstream Channel draft capability contract across applications.
- [ ] Add navigation/persistence tests for later CNB execution, including same-document time origin, cross-document time origin, refresh, and back/forward.

### Phase 7 — budgets and reversal of the old contract

- [ ] Make the budget checker select the registry-declared entry/renderer and complete transitive manifest closure for every representative route.
- [ ] Add minimum representative budgets for Website, Forum, Store, Account, Staff, Admin, and Website Preview.
- [ ] Remove CE's optional Channel budget. EE will add Channel only in its downstream adapter after inheriting CE.
- [ ] Replace tests that assert all `/app/**` links share one SPA with tests that assert same-app Inertia and cross-app documents.
- [ ] Add static coverage proving every current Vue page has exactly one product owner or one explicit Website Preview projection and no resolver has a negative-glob fallback.

### Phase 8 — verification and delivery

- [ ] Local verification is limited to syntax/format checks, manual static inspection, and `git diff --check`; local application startup is deferred until the final three-layer integration.
- [ ] Do not run any Rails, Node, or Go test file locally. Do not run TypeScript typecheck or any Vite, Astro, or Go build locally.
- [ ] Use CNB for every Rails/Node/Go test, TypeScript typecheck, Vite/Astro/Go build, generated-resource verification, per-entry budget check, and automated browser acceptance.
- [ ] In CNB verify direct load, refresh, back/forward, same-app navigation, cross-app document navigation, Simplified Chinese/English, light/dark theme, guest/authenticated sessions, saved drafts, Website Preview, and responsive/accessibility smoke coverage.
- [ ] Commit only the reviewed CE boundary files directly to `main`; keep unrelated report/appeal work out of the index and do not push.
- [ ] Confirm CE is clean and the focused checks passed before any later ordinary merge into EE. EE Channel and EE-PVP player PVP remain separate downstream adapter commits.

## Prospective CE file ownership

### New boundary-owned paths

- `config/frontend_applications/schema.json`
- `config/frontend_applications/base/*.json`
- `config/frontend_applications/contributions/.gitkeep`
- `app/services/frontend/application_registry.rb`
- `app/controllers/concerns/inertia_application_boundary.rb`
- `app/javascript/lib/frontendApplications.ts`
- `app/javascript/lib/createInertiaApplication.ts`
- `app/javascript/lib/applicationNavigation.ts`
- `app/javascript/lib/unsavedForms.ts`
- `app/javascript/lib/localeBridge.ts`
- `app/javascript/lib/themeBootstrap.ts`
- `app/javascript/frontend-application-adapters/**/*.ts`
- `app/javascript/components/ApplicationErrorBoundary.vue`
- `app/javascript/entrypoints/website-document.ts`
- `app/javascript/entrypoints/forum.ts`
- `app/javascript/entrypoints/store.ts`
- `app/javascript/entrypoints/account.ts`
- `app/javascript/entrypoints/staff.ts`
- `app/javascript/entrypoints/website-preview.ts`
- `app/javascript/styles/applications/*.css`
- `app/javascript/locales/domains/{en,zh-CN}/*.ts` (generated)
- `scripts/generate-frontend-application-locales.mjs`
- `scripts/check-frontend-application-boundaries.mjs`
- focused Ruby, JavaScript, and browser boundary tests under `test/`

### Existing paths expected to change after the gate opens

- Server/layout: `app/controllers/application_controller.rb`, `app/controllers/concerns/inertia_shared_props.rb`, `app/views/layouts/inertia.html.erb`, `app/views/layouts/inertia_admin.html.erb`, Website controllers/layouts, locale/session concerns, and Website Preview controllers.
- Entries/navigation: `app/javascript/entrypoints/inertia.ts` (remove after cutover), `app/javascript/entrypoints/admin.ts`, `app/javascript/lib/portalNavigation.ts`, `app/javascript/lib/adminNavigation.ts`, and `app/javascript/lib/intentPrefetch.ts`.
- Shell/resources/build: `app/javascript/lib/i18n.ts`, `app/javascript/lib/useTheme.ts`, `app/javascript/lib/usePortalNav.ts`, `app/javascript/layouts/PortalLayout.vue`, `app/javascript/layouts/WebsiteLayout.vue`, `app/javascript/layouts/StaffLayout.vue`, `vite.config.ts`, `package.json`, `scripts/check-vite-budgets.mjs`, and `scripts/check-frontend-i18n.mjs`.
- Staff correction: `app/controllers/community/moderation/approvals_controller.rb`, `app/javascript/pages/Community/Moderation/Approvals/Index.vue`, plus their new Staff destinations.
- Existing static/integration/E2E tests that explicitly name `inertia.ts`, Admin-only navigation, Website preview layout, locale loading, shell styles, or the old `/app` SPA contract.

## Released coordination baseline (2026-08-23)

- The independent report/appeal implementation is integrated in CE history.
- The user confirmed CE `main` safe and frozen at `b385428f3120a2767af2d7329f6fcccc4387d985`; the only initial status entry for this task was this untracked plan.
- Before every implementation commit, re-check the index and worktree, stage only explicitly owned files, and stop if unrelated work appears.
