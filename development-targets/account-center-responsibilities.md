# Account center page responsibilities and entry reachability

## Ownership

- Owner: CE.
- Reason: `/app` entry behavior, the shared account center, identity self-service, and Website CMS administration are edition-neutral platform responsibilities. EE and EE-PVP must inherit fixes through ordinary `CE -> EE -> EE-PVP` merges instead of reimplementing them downstream.

## Confirmed current-state findings

- `routes.app` and both Staff return controls target `/app`, but CE currently declares no `GET /app` route. The active `frontend-application-boundaries` target explicitly owns `/app` as a document launcher or redirect, so that route fix is handed off to that task and is excluded here.
- The current Admin Website submenu destinations, controller component names, and positive `Admin/**` resolver are statically coherent; earlier CE work already repaired the invalid navigation-item edit route and the original entry failures. Action-level authorization remains inconsistent: read-only staff receive navigation/theme write controls, publish-only staff receive Archive controls that also require edit permission, and lifecycle revision deep links can return to a recycle-bin page the reader cannot enter.
- Navigation update and theme deletion already have backend routes, but the Admin UI exposes neither operation. Navigation update also checks its invalid-page flag before parsing the parameters that set that flag.
- Ordinary theme create/update accepts an `active` parameter even though activation has a publish-only action, allowing edit-only staff to bypass publication authorization. Theme deletion also leaves discarded or purged pages behind the default lifecycle scope, so the database foreign key can reject deletion.
- `/admin/website` itself has no landing route, the page/article form preview action has no current UI, and the preview projection has no Admin return path. Those route and preview semantics are explicitly owned by `frontend-application-boundaries`, so they are handed off rather than implemented concurrently here.
- `Account/Show.vue` is a real state dashboard at the top, but it still presents Forum destinations as four large action lists. Nine of those independently routed pages currently have no other discoverable UI entry; they must remain reachable here until the application-boundary navigation owner supplies a Forum hub, but can be reduced to compact semantic link groups instead of repeated icon/description/action rows.
- The account dashboard, profile form, and password form contain isolated inline layout styles even though the same spacing, width, and text-wrapping behavior is available through existing application utility classes.

## Requirements

- Keep the account center focused on identity summary, security state, items requiring attention, linked Minecraft identity, and contextual account-management actions.
- Preserve direct access from dashboard state to the independent notification, conversation, draft, profile, password, security, Minecraft link, session, and data-export pages.
- Keep Forum pages that otherwise have no discoverable UI entry reachable through three compact semantic link groups. Omit Community Preferences because the user menu already exposes it, and omit watched-tag topics because the watched-tags page already links to it.
- Preserve Forum and Minecraft feature-flag behavior and do not expose disabled-product actions.
- Make every CMS control changed here match its server permission: theme and navigation writes require read plus edit, and theme activation requires read plus publish.
- Expose the existing navigation update and persisted-theme delete operations through the current Arco forms, with the existing confirmation facade and no new primitive.
- Keep theme activation exclusively behind the publish-authorized activation action, and detach every page across active, discarded, or purged lifecycle states before deleting a theme.
- Make discarded/purged revision return paths fall back to the authorized page/article list when the reader cannot enter the recycle bin.
- Use only existing `@mcweb/ui`/Arco components, application utilities, and layout tokens. Add no local primitive, gradient, moving hover treatment, or persistent decorative focus style.
- Replace account/profile/password inline layout styles with existing utility classes; do not modify application entrypoints, layouts, resolver code, shared navigation, or route classification.

## Scoped implementation files

- `app/javascript/pages/Account/Show.vue`
- `app/javascript/pages/Identity/Profiles/Show.vue`
- `app/javascript/pages/Identity/Passwords/Edit.vue`
- `app/controllers/admin/website/themes_controller.rb`
- `app/controllers/admin/website/nav_items_controller.rb`
- `app/controllers/admin/website/page_revisions_controller.rb`
- `app/controllers/admin/website/article_revisions_controller.rb`
- `app/javascript/pages/Admin/Website/NavItems/Index.vue`
- `app/javascript/pages/Admin/Website/Themes/Form.vue`
- `test/integration/admin/website_cms_action_reachability_test.rb`
- `test/javascript/admin_website_permission_ui_test.ts`
- `test/javascript/account_center_responsibility_test.ts`

## Explicit coordination exclusions

- `config/routes.rb`, `app/javascript/lib/routes.ts`, `app/javascript/entrypoints/**`, `app/javascript/layouts/**`, `app/javascript/lib/usePortalNav.ts`, `app/javascript/lib/portalNavigation.ts`, and all frontend application registry/boundary files remain owned by `frontend-application-boundaries`.
- `config/routes.rb`, Admin Website preview renderers, preview controls/return projections, `/admin/website` landing behavior, and the complete-resource route declarations remain handed off to `frontend-application-boundaries`.
- Page/Article Archive action visibility is also handed off because the necessary controller files contain the boundary-owned preview actions; the server already rejects the incomplete permission combination.

## Delivery checklist

- [x] Replace the duplicated Forum action lists with compact groups while retaining destinations that have no other discoverable entry.
- [x] Keep identity, security, Minecraft, sessions, and data-export responsibilities visibly separated.
- [x] Remove inline layout styles from the three scoped account/identity pages with existing utility classes.
- [x] Hide CMS mutation controls that the current administrator cannot execute and align theme write entry prerequisites.
- [x] Restore the existing navigation update and theme delete operations to reachable CMS UI flows without discarding failed edit state.
- [x] Keep theme activation behind publish permission and make deletion cover lifecycle-scoped page references.
- [x] Keep revision back paths inside the reader's authorized CMS surface.
- [x] Add isolated source and integration contracts without editing boundary-owned test files.
- [x] Review only the scoped diff; do not run local tests, syntax checks, type checks, builds, lint, services, browsers, or CNB.
- [x] Commit only the explicitly scoped paths directly to CE `main` and do not push.

## Deferred verification

- CNB: account source contract, JavaScript suite, TypeScript checking, and production bundle.
- Main task on the user's machine: `/app` launcher behavior after the boundary handoff, authenticated direct loads, refresh/back paths, feature-flag variants, and desktop/mobile Edge acceptance for the account and Website CMS journeys.
