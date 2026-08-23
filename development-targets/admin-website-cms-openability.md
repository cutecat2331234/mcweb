# Admin Website CMS openability

## Ownership

- Owner: CE.
- Reason: the Admin Website entry, Rails CMS routes, Inertia application ownership, and shared CMS pages are edition-neutral platform capabilities. EE and EE-PVP must inherit any repair through ordinary `CE -> EE -> EE-PVP` merges.

## Requirement

- An authorized administrator can open every Website CMS destination exposed by the Admin sidebar: pages, articles, navigation, recycle bin, themes, and frontend templates.
- Each sidebar URL must match a Rails GET route and an Admin controller action with the same module and permission contract.
- Every controller-rendered Inertia component must be owned by the Admin application manifest and positively resolved by the Admin entrypoint.
- Every rendered component path must exist on disk and receive the required props for its initial render.
- Preview remains a native document transition into the Website Preview application; it must not make the Admin resolver load public Website components.
- APP controls remain on the existing `@mcweb/ui`/Arco stack. This task adds no visual polish or new control primitives.
- Verification in this task is static inspection only. Tests, builds, typechecks, lint, syntax checks, diff checks, browsers, and CNB are explicitly out of scope.

## Task checklist

- [x] Trace Admin Website sidebar destinations and their visibility requirements.
- [x] Trace Rails routes, controllers, actions, permission gates, and redirect entry.
- [x] Compare Inertia application manifest ownership with the Admin positive resolver.
- [x] Inventory controller component names against the on-disk Vue pages.
- [x] Compare each CMS entry component's required props with its controller payload.
- [x] Repair only a statically proven openability blocker, if one exists. No blocker is present at the inspected HEAD, so no runtime code is changed.
- [x] Record the final static evidence and commit only this evidence file to `main`.

## Static reachability evidence

| Admin destination | Rails owner | Inertia component | Required initial props | Result |
| --- | --- | --- | --- | --- |
| `/admin/website/pages` | `Admin::Website::PagesController#index` | `Admin/Generic/Index` | `title`, `columns`, `rows`; `actions` supplied | Aligned |
| `/admin/website/articles` | `Admin::Website::ArticlesController#index` | `Admin/Generic/Index` | `title`, `columns`, `rows`; `actions` supplied | Aligned |
| `/admin/website/nav_items` | `Admin::Website::NavItemsController#index` | `Admin/Website/NavItems/Index` | `title`, `items`, `pages`, `submitUrl`, `reorderUrl`, `canEdit` | Aligned |
| `/admin/website/recycle-bin` | `Admin::Website::RecycleBinController#index` | `Admin/Website/Recovery/Index` | `title`, `rows`, `pagesUrl`, `articlesUrl` | Aligned |
| `/admin/website/themes` | `Admin::Website::ThemesController#index` | `Admin/Generic/Index` | `title`, `columns`, `rows`; `actions` supplied | Aligned |
| `/admin/frontend/templates` | `Admin::Frontend::TemplatesController#index` | `Admin/Frontend/Templates/Index` | `templates`, `activeWebsiteTemplate`, `activePortalTemplate`, `uploadUrl`, `starterDownloadUrl` | Aligned |

Additional direct-link evidence:

- `config/routes.rb` declares the Website namespace landing redirect, CRUD/read routes, recycle-bin routes, navigation routes, theme revision routes, and preview GET routes under Admin.
- `Admin::Website::HomeController` redirects `/admin/website` to the first CMS destination the current administrator can read.
- `Admin::Website::BaseController` and `Admin::Frontend::BaseController` both enforce the `website` Admin module. Destination controllers separately enforce their matching read/edit/publish/recovery permission.
- `config/frontend_applications/base/admin.json` owns `Admin/Generic/`, `Admin/Frontend/`, and `Admin/Website/`, and classifies `/admin/**` GET requests as Admin Inertia pages.
- `app/javascript/entrypoints/admin.ts` positively discovers the same three page roots, including all nested Website form, recovery, revision, and theme revision components.
- Exact Website Preview routes have higher manifest priority than the Admin catch-all. Their controllers render projected `Website/Pages/Show` or `Website/Articles/Show` through `Frontend::WebsiteRenderer.preview`, while Admin actions mark preview as hard navigation.
- Every `render inertia:` name under `app/controllers/admin/website/` has a matching positive resolver entry and on-disk Vue component. Page/article forms, discard, revision, recovery, theme, and theme-revision controllers supply every non-optional prop declared by those components.
- Existing source contracts cover the same reachability chain in `test/integration/admin/admin_entry_permission_coherence_test.rb`, `test/integration/admin/website_cms_action_reachability_test.rb`, and `test/javascript/admin_arco_pages_test.ts`; they were inspected but not executed in this task.

## Conclusion

At CE `8d12ef60a39b4ae78ef78418da10e23b965ebad4`, including the intervening contribution-navigation and contribution-page-root changes after the initial `47b5a193` inspection baseline, there is no statically evidenced URL, route/controller, manifest ownership, positive resolver, component-file, or required-prop mismatch that would prevent the Admin Website CMS from opening. Runtime code changes would therefore be speculative and are intentionally omitted. The reported failure still requires live response/error evidence in a separately authorized browser or server-validation pass to distinguish permissions, database state, stale assets/service workers, or another runtime-only cause.
